-- Lease-activation cohort × days-to-first-payment (cumulative). Adapted from lease_funnel_events.sql.
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
first_pay AS (
  SELECT cd.lease_id, MIN(sp.created) AS first_payment_date
  FROM first_active_ex cd JOIN fivetran_database.analytics.stripe_payments sp ON cd.lease_id=sp.lease_id
  WHERE sp.amounttotransfer>0 AND sp.type IN ('charge','payment','cash payment')
    AND sp.created >= cd.first_active_date AND sp.created <= '2026-05-24'
  GROUP BY 1
),
joined AS (
  SELECT cd.lease_id, cd.LeaseActivationMonth AS cohort_month, cd.cohort_status, cd.first_active_date,
    DATEDIFF('day', cd.first_active_date, fp.first_payment_date) AS dtp
  FROM first_active_ex cd LEFT JOIN first_pay fp ON cd.lease_id=fp.lease_id
)
SELECT cohort_month, cohort_status,
  COUNT(*) AS total,
  MAX(first_active_date) AS last_active,
  COUNT(CASE WHEN dtp BETWEEN 0 AND 7  THEN 1 END) AS c7,
  COUNT(CASE WHEN dtp BETWEEN 0 AND 14 THEN 1 END) AS c14,
  COUNT(CASE WHEN dtp BETWEEN 0 AND 30 THEN 1 END) AS c30,
  COUNT(CASE WHEN dtp BETWEEN 0 AND 45 THEN 1 END) AS c45,
  COUNT(CASE WHEN dtp BETWEEN 0 AND 90 THEN 1 END) AS c90
FROM joined GROUP BY 1,2 ORDER BY 1,2;
