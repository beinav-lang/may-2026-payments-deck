-- v7: invite + pageview keyed on properties:sentToId (recipient). register=tenant portalInfo. 25->24 cohort, ±45d.
WITH new_leases AS (
  SELECT lease_id FROM fivetran_database.analytics.leases_daily_snapshot
  GROUP BY lease_id HAVING MIN(snapshot_date) >= '2025-09-01'
),
-- PM tenure (Stripe only, NO snapshot): each PM's first-ever payment cycle.
pm_first AS (
  SELECT je.dbtenant AS pm,
    MIN(DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD(month,1,p.created) ELSE p.created END)) AS pm_first_cycle
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.journalentries je ON je._id = p.je_id
  WHERE p.amounttotransfer>0 AND p.type IN ('charge','payment','cash payment') AND je.dbtenant IS NOT NULL
  GROUP BY 1
),
first_active AS (
  -- cohort = PM tenure at lease activation: PM in its first 3 months on platform (<=2 mo since first Stripe payment) => Onboarding.
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
  SELECT ltm.lease_id, MIN(t.portalinfo:invitationAcceptedAt::timestamp) AS registered_date
  FROM lease_tenant ltm JOIN airbyte_database.doorloop.tenants t ON t._id=ltm.tenant_id
  WHERE t.portalinfo:invitationAcceptedAt IS NOT NULL GROUP BY 1
),
lease_invite_ev AS (
  SELECT lt.lease_id, MIN(e."timestamp"::timestamp) AS invite_date
  FROM lease_tenant lt JOIN posthog_db.events.events_doorloop e ON e."properties":"sentToId"::string = lt.tenant_id
  WHERE e."event"='invitation_sent' AND e."timestamp" >= '2025-07-01'
  GROUP BY 1
),
lease_pv_ph AS (
  SELECT lt.lease_id, MIN(e."timestamp"::timestamp) AS first_pv
  FROM lease_tenant lt JOIN posthog_db.events.events_doorloop e ON e."properties":"sentToId"::string = lt.tenant_id
  WHERE e."event"='invitation_pageview' AND e."timestamp" >= '2025-07-01'
  GROUP BY 1
),
cohort_data AS (
  SELECT fa.*, lr.registered_date, iv.invite_date, pv.first_pv,
    CASE WHEN iv.invite_date IS NOT NULL AND ABS(DATEDIFF('day', fa.first_active_date, iv.invite_date))<=45 THEN 1 ELSE 0 END AS is_invited,
    CASE WHEN pv.first_pv IS NOT NULL AND ABS(DATEDIFF('day', fa.first_active_date, pv.first_pv))<=45 THEN 1 ELSE 0 END AS is_pageview,
    CASE WHEN lr.registered_date IS NOT NULL AND ABS(DATEDIFF('day', fa.first_active_date, lr.registered_date))<=45 THEN 1 ELSE 0 END AS is_portal_active
  FROM first_active_ex fa
  LEFT JOIN lease_register lr ON fa.lease_id=lr.lease_id
  LEFT JOIN lease_invite_ev iv ON fa.lease_id=iv.lease_id
  LEFT JOIN lease_pv_ph pv ON fa.lease_id=pv.lease_id
),
fpc AS (
  SELECT cd.lease_id, MIN(sp.created) AS first_payment_date
  FROM cohort_data cd JOIN fivetran_database.analytics.stripe_payments sp ON cd.lease_id=sp.lease_id
  WHERE cd.is_portal_active=1 AND sp.created>=cd.first_active_date AND sp.created<=DATEADD('day',45,cd.first_active_date) AND sp.amounttotransfer>0
  GROUP BY 1
),
ret AS (
  SELECT fp.lease_id,
    MAX(CASE WHEN sp.created>fp.first_payment_date AND sp.created<=DATEADD('day',45,fp.first_payment_date) AND sp.amounttotransfer>0 THEN 1 ELSE 0 END) AS retained_p1,
    MAX(CASE WHEN sp.created>DATEADD('day',45,fp.first_payment_date) AND sp.created<=DATEADD('day',90,fp.first_payment_date) AND sp.amounttotransfer>0 THEN 1 ELSE 0 END) AS retained_p2
  FROM fpc fp JOIN fivetran_database.analytics.stripe_payments sp ON fp.lease_id=sp.lease_id GROUP BY 1
)
SELECT cd.LeaseActivationMonth, cd.cohort_status,
  COUNT(cd.lease_id) AS total,
  COUNT(CASE WHEN cd.is_invited=1 THEN 1 END) AS invited,
  COUNT(CASE WHEN cd.is_pageview=1 THEN 1 END) AS pageview,
  COUNT(CASE WHEN cd.is_portal_active=1 THEN 1 END) AS registered,
  COUNT(fpc.lease_id) AS converted,
  COUNT(CASE WHEN ret.retained_p1=1 THEN 1 END) AS retained_p1,
  COUNT(CASE WHEN ret.retained_p2=1 THEN 1 END) AS retained_p2
FROM cohort_data cd
LEFT JOIN fpc ON cd.lease_id=fpc.lease_id
LEFT JOIN ret ON cd.lease_id=ret.lease_id
GROUP BY 1,2 ORDER BY 1,2;
