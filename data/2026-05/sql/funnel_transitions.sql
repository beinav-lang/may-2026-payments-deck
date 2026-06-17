-- Funnel-step transitions × activation cohort × days-to-event (cumulative).
-- Extends lease_funnel_events.sql: per-lease invite/register/1st-pay/2nd-pay dates,
-- then cumulative % completing each transition within 7/14/30/45/90 days of its start.
WITH new_leases AS (
  SELECT lease_id FROM fivetran_database.analytics.leases_daily_snapshot
  GROUP BY lease_id HAVING MIN(snapshot_date) >= '2025-09-01'
),
pm_first AS (
  SELECT je.dbtenant AS pm,
    MIN(DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD(month,1,p.created) ELSE p.created END)) AS pm_first_cycle
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.journalentries je ON je._id = p.je_id
  WHERE p.amounttotransfer>0 AND p.type IN ('charge','payment','cash payment') AND je.dbtenant IS NOT NULL
  GROUP BY 1
),
first_active AS (
  SELECT lease_id, first_active_date, dbtenant, LeaseActivationMonth,
    CASE WHEN pm_first_cycle IS NULL OR DATEDIFF('month', pm_first_cycle, LeaseActivationMonth) <= 2
         THEN 'Onboarding' ELSE 'Mature' END AS cohort_status
  FROM (
    SELECT lds.lease_id, lds.snapshot_date AS first_active_date, lds.dbtenant, pmf.pm_first_cycle,
      DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM lds.snapshot_date)>=25 THEN DATEADD(month,1,lds.snapshot_date) ELSE lds.snapshot_date END) AS LeaseActivationMonth,
      ROW_NUMBER() OVER (PARTITION BY lds.lease_id ORDER BY lds.snapshot_date) AS rn
    FROM fivetran_database.analytics.leases_daily_snapshot lds
    INNER JOIN new_leases nl ON lds.lease_id = nl.lease_id
    LEFT JOIN pm_first pmf ON lds.dbtenant = pmf.pm
    WHERE lds.status='ACTIVE' AND lds.snapshot_date BETWEEN '2025-09-01' AND '2026-05-24'
      AND lds.rent_frequency IN ('Monthly','Every2Weeks','Weekly','Daily') AND lds.merchant_account_flag=1
  ) WHERE rn=1 AND LeaseActivationMonth BETWEEN '2025-09-01' AND '2026-05-01'
),
lease_tenant AS (
  SELECT DISTINCT lb._id AS lease_id, f.value:tenant::string AS tenant_id
  FROM airbyte_database.doorloop.leases lb, LATERAL FLATTEN(input => lb.tenants) f
  WHERE lb.deleted='false'
),
tenant_lease_count AS (SELECT tenant_id, COUNT(DISTINCT lease_id) AS n_leases FROM lease_tenant GROUP BY 1),
tenant_accept AS (
  SELECT t._id AS tenant_id, t.portalinfo:invitationAcceptedAt::timestamp AS accepted_at
  FROM airbyte_database.doorloop.tenants t WHERE t.portalinfo:invitationAcceptedAt IS NOT NULL
),
retenant_leases AS (
  SELECT DISTINCT fa.lease_id FROM first_active fa
  JOIN lease_tenant lt ON lt.lease_id=fa.lease_id
  JOIN tenant_lease_count tc ON tc.tenant_id=lt.tenant_id
  JOIN tenant_accept ta ON ta.tenant_id=lt.tenant_id
  WHERE tc.n_leases>=2 AND ta.accepted_at < fa.first_active_date
),
first_active_ex AS (
  SELECT fa.* FROM first_active fa LEFT JOIN retenant_leases r ON r.lease_id=fa.lease_id WHERE r.lease_id IS NULL
),
lease_register AS (
  SELECT ltm.lease_id, MIN(t.portalinfo:invitationAcceptedAt::timestamp)::date AS registered_date
  FROM lease_tenant ltm JOIN airbyte_database.doorloop.tenants t ON t._id=ltm.tenant_id
  WHERE t.portalinfo:invitationAcceptedAt IS NOT NULL
    AND t.portalinfo:invitationAcceptedAt::timestamp::date <= '2026-06-15' GROUP BY 1
),
lease_invite_ev AS (
  SELECT lt.lease_id, MIN(e."timestamp"::timestamp)::date AS invite_date
  FROM lease_tenant lt JOIN posthog_db.events.events_doorloop e ON e."properties":"sentToId"::string = lt.tenant_id
  WHERE e."event"='invitation_sent' AND e."timestamp" >= '2025-07-01' AND e."timestamp"::date <= '2026-06-15'
  GROUP BY 1
),
paydays AS (
  SELECT lease_id, pay_date, ROW_NUMBER() OVER (PARTITION BY lease_id ORDER BY pay_date) rn
  FROM (
    SELECT DISTINCT sp.lease_id, sp.created AS pay_date
    FROM fivetran_database.analytics.stripe_payments sp
    JOIN first_active_ex cd ON cd.lease_id=sp.lease_id
    WHERE sp.amounttotransfer>0 AND sp.type IN ('charge','payment','cash payment')
      AND sp.created >= cd.first_active_date AND sp.created <= '2026-06-15'
  )
),
pay AS (
  SELECT lease_id,
    MAX(CASE WHEN rn=1 THEN pay_date END) AS first_payment_date,
    MAX(CASE WHEN rn=2 THEN pay_date END) AS second_payment_date
  FROM paydays GROUP BY 1
),
e AS (
  SELECT cd.lease_id, cd.LeaseActivationMonth AS cohort_month, cd.cohort_status,
    cd.first_active_date AS act_date,
    iv.invite_date, lr.registered_date, pay.first_payment_date, pay.second_payment_date
  FROM first_active_ex cd
  LEFT JOIN lease_invite_ev iv ON cd.lease_id=iv.lease_id
  LEFT JOIN lease_register lr ON cd.lease_id=lr.lease_id
  LEFT JOIN pay ON cd.lease_id=pay.lease_id
)
SELECT cohort_month, cohort_status, 'T0_act_pay' AS metric,
  COUNT(act_date) AS reach,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',7,act_date) <= '2026-06-15' THEN 1 END) AS obs7,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',7,act_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',act_date,first_payment_date) BETWEEN 0 AND 7 THEN 1 END) AS hit7,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',14,act_date) <= '2026-06-15' THEN 1 END) AS obs14,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',14,act_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',act_date,first_payment_date) BETWEEN 0 AND 14 THEN 1 END) AS hit14,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',30,act_date) <= '2026-06-15' THEN 1 END) AS obs30,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',30,act_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',act_date,first_payment_date) BETWEEN 0 AND 30 THEN 1 END) AS hit30,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',45,act_date) <= '2026-06-15' THEN 1 END) AS obs45,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',45,act_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',act_date,first_payment_date) BETWEEN 0 AND 45 THEN 1 END) AS hit45,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',90,act_date) <= '2026-06-15' THEN 1 END) AS obs90,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',90,act_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',act_date,first_payment_date) BETWEEN 0 AND 90 THEN 1 END) AS hit90
FROM e GROUP BY 1,2
UNION ALL
SELECT cohort_month, cohort_status, 'T1_act_invite' AS metric,
  COUNT(act_date) AS reach,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',7,act_date) <= '2026-06-15' THEN 1 END) AS obs7,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',7,act_date) <= '2026-06-15' AND invite_date IS NOT NULL AND ABS(DATEDIFF('day',act_date,invite_date)) <= 7 THEN 1 END) AS hit7,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',14,act_date) <= '2026-06-15' THEN 1 END) AS obs14,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',14,act_date) <= '2026-06-15' AND invite_date IS NOT NULL AND ABS(DATEDIFF('day',act_date,invite_date)) <= 14 THEN 1 END) AS hit14,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',30,act_date) <= '2026-06-15' THEN 1 END) AS obs30,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',30,act_date) <= '2026-06-15' AND invite_date IS NOT NULL AND ABS(DATEDIFF('day',act_date,invite_date)) <= 30 THEN 1 END) AS hit30,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',45,act_date) <= '2026-06-15' THEN 1 END) AS obs45,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',45,act_date) <= '2026-06-15' AND invite_date IS NOT NULL AND ABS(DATEDIFF('day',act_date,invite_date)) <= 45 THEN 1 END) AS hit45,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',90,act_date) <= '2026-06-15' THEN 1 END) AS obs90,
  COUNT(CASE WHEN act_date IS NOT NULL AND DATEADD('day',90,act_date) <= '2026-06-15' AND invite_date IS NOT NULL AND ABS(DATEDIFF('day',act_date,invite_date)) <= 90 THEN 1 END) AS hit90
FROM e GROUP BY 1,2
UNION ALL
SELECT cohort_month, cohort_status, 'T2_invite_reg' AS metric,
  COUNT(invite_date) AS reach,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',7,invite_date) <= '2026-06-15' THEN 1 END) AS obs7,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',7,invite_date) <= '2026-06-15' AND registered_date IS NOT NULL AND DATEDIFF('day',invite_date,registered_date) BETWEEN 0 AND 7 THEN 1 END) AS hit7,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',14,invite_date) <= '2026-06-15' THEN 1 END) AS obs14,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',14,invite_date) <= '2026-06-15' AND registered_date IS NOT NULL AND DATEDIFF('day',invite_date,registered_date) BETWEEN 0 AND 14 THEN 1 END) AS hit14,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',30,invite_date) <= '2026-06-15' THEN 1 END) AS obs30,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',30,invite_date) <= '2026-06-15' AND registered_date IS NOT NULL AND DATEDIFF('day',invite_date,registered_date) BETWEEN 0 AND 30 THEN 1 END) AS hit30,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',45,invite_date) <= '2026-06-15' THEN 1 END) AS obs45,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',45,invite_date) <= '2026-06-15' AND registered_date IS NOT NULL AND DATEDIFF('day',invite_date,registered_date) BETWEEN 0 AND 45 THEN 1 END) AS hit45,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',90,invite_date) <= '2026-06-15' THEN 1 END) AS obs90,
  COUNT(CASE WHEN invite_date IS NOT NULL AND DATEADD('day',90,invite_date) <= '2026-06-15' AND registered_date IS NOT NULL AND DATEDIFF('day',invite_date,registered_date) BETWEEN 0 AND 90 THEN 1 END) AS hit90
FROM e GROUP BY 1,2
UNION ALL
SELECT cohort_month, cohort_status, 'T3_reg_pay' AS metric,
  COUNT(registered_date) AS reach,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',7,registered_date) <= '2026-06-15' THEN 1 END) AS obs7,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',7,registered_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',registered_date,first_payment_date) BETWEEN 0 AND 7 THEN 1 END) AS hit7,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',14,registered_date) <= '2026-06-15' THEN 1 END) AS obs14,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',14,registered_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',registered_date,first_payment_date) BETWEEN 0 AND 14 THEN 1 END) AS hit14,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',30,registered_date) <= '2026-06-15' THEN 1 END) AS obs30,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',30,registered_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',registered_date,first_payment_date) BETWEEN 0 AND 30 THEN 1 END) AS hit30,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',45,registered_date) <= '2026-06-15' THEN 1 END) AS obs45,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',45,registered_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',registered_date,first_payment_date) BETWEEN 0 AND 45 THEN 1 END) AS hit45,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',90,registered_date) <= '2026-06-15' THEN 1 END) AS obs90,
  COUNT(CASE WHEN registered_date IS NOT NULL AND DATEADD('day',90,registered_date) <= '2026-06-15' AND first_payment_date IS NOT NULL AND DATEDIFF('day',registered_date,first_payment_date) BETWEEN 0 AND 90 THEN 1 END) AS hit90
FROM e GROUP BY 1,2
UNION ALL
SELECT cohort_month, cohort_status, 'T4_pay_pay2' AS metric,
  COUNT(first_payment_date) AS reach,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',7,first_payment_date) <= '2026-06-15' THEN 1 END) AS obs7,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',7,first_payment_date) <= '2026-06-15' AND second_payment_date IS NOT NULL AND DATEDIFF('day',first_payment_date,second_payment_date) BETWEEN 0 AND 7 THEN 1 END) AS hit7,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',14,first_payment_date) <= '2026-06-15' THEN 1 END) AS obs14,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',14,first_payment_date) <= '2026-06-15' AND second_payment_date IS NOT NULL AND DATEDIFF('day',first_payment_date,second_payment_date) BETWEEN 0 AND 14 THEN 1 END) AS hit14,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',30,first_payment_date) <= '2026-06-15' THEN 1 END) AS obs30,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',30,first_payment_date) <= '2026-06-15' AND second_payment_date IS NOT NULL AND DATEDIFF('day',first_payment_date,second_payment_date) BETWEEN 0 AND 30 THEN 1 END) AS hit30,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',45,first_payment_date) <= '2026-06-15' THEN 1 END) AS obs45,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',45,first_payment_date) <= '2026-06-15' AND second_payment_date IS NOT NULL AND DATEDIFF('day',first_payment_date,second_payment_date) BETWEEN 0 AND 45 THEN 1 END) AS hit45,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',90,first_payment_date) <= '2026-06-15' THEN 1 END) AS obs90,
  COUNT(CASE WHEN first_payment_date IS NOT NULL AND DATEADD('day',90,first_payment_date) <= '2026-06-15' AND second_payment_date IS NOT NULL AND DATEDIFF('day',first_payment_date,second_payment_date) BETWEEN 0 AND 90 THEN 1 END) AS hit90
FROM e GROUP BY 1,2
ORDER BY 3,1,2;
