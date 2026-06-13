-- kpi_dashboard.sql + RE-TENANT EXCLUSION (v2), window extended through May 2026.
-- Re-tenant exclusion: drop a lease if ANY of its tenants accepted a portal invite
-- (invitationAcceptedAt) BEFORE this lease's activation AND is on >=2 leases.
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
tenant_lease_count AS (
  SELECT tenant_id, COUNT(DISTINCT lease_id) AS n_leases FROM lease_tenant GROUP BY 1
),
tenant_accept AS (
  SELECT t._id AS tenant_id, t.portalinfo:invitationAcceptedAt::timestamp AS accepted_at
  FROM airbyte_database.doorloop.tenants t WHERE t.portalinfo:invitationAcceptedAt IS NOT NULL
),
retenant_leases AS (
  SELECT DISTINCT fa.lease_id
  FROM first_active fa
  JOIN lease_tenant lt ON lt.lease_id = fa.lease_id
  JOIN tenant_lease_count tc ON tc.tenant_id = lt.tenant_id
  JOIN tenant_accept ta ON ta.tenant_id = lt.tenant_id
  WHERE tc.n_leases >= 2 AND ta.accepted_at < fa.first_active_date
),
first_active_ex AS (
  SELECT fa.* FROM first_active fa
  LEFT JOIN retenant_leases r ON r.lease_id = fa.lease_id
  WHERE r.lease_id IS NULL
),
lease_portal_agg AS (
  SELECT ltm.lease_id, MIN(t.portalinfo:invitationAcceptedAt::timestamp) AS lease_first_registered_date
  FROM lease_tenant ltm
  JOIN airbyte_database.doorloop.tenants t ON t._id = ltm.tenant_id
  WHERE t.portalinfo IS NOT NULL AND t.portalinfo:invitationAcceptedAt IS NOT NULL
  GROUP BY 1
),
lease_invite_agg AS (
  SELECT ltm.lease_id, MIN(t.portalinfo:invitationLastSentAt::timestamp) AS first_invite_sent_date
  FROM lease_tenant ltm
  JOIN airbyte_database.doorloop.tenants t ON t._id = ltm.tenant_id
  WHERE t.portalinfo:invitationLastSentAt IS NOT NULL
  GROUP BY 1
),
cohort_data AS (
  SELECT fa.*, lp.lease_first_registered_date, li.first_invite_sent_date,
    CASE WHEN lp.lease_first_registered_date IS NOT NULL AND ABS(DATEDIFF('day', fa.first_active_date, lp.lease_first_registered_date))<=45 THEN 1 ELSE 0 END AS is_portal_active,
    CASE WHEN li.first_invite_sent_date IS NOT NULL AND ABS(DATEDIFF('day', fa.first_active_date, li.first_invite_sent_date))<=45 THEN 1 ELSE 0 END AS is_invite_sent
  FROM first_active_ex fa
  LEFT JOIN lease_portal_agg lp ON fa.lease_id=lp.lease_id
  LEFT JOIN lease_invite_agg li ON fa.lease_id=li.lease_id
),
first_payment_conversion AS (
  SELECT cd.lease_id, 1 AS converted
  FROM cohort_data cd JOIN fivetran_database.analytics.stripe_payments sp ON cd.lease_id=sp.lease_id
  WHERE cd.is_portal_active=1 AND sp.created>=cd.first_active_date AND sp.created<=DATEADD('day',45,cd.first_active_date) AND sp.amounttotransfer>0
  GROUP BY 1
),
first_payment AS (
  SELECT cd.lease_id, MIN(sp.created) AS first_payment_date
  FROM cohort_data cd JOIN fivetran_database.analytics.stripe_payments sp ON cd.lease_id=sp.lease_id
  WHERE cd.is_portal_active=1 AND sp.created>=cd.first_active_date AND sp.created<=DATEADD('day',45,cd.first_active_date) AND sp.amounttotransfer>0
  GROUP BY 1
),
retention_check AS (
  SELECT fp.lease_id,
    MAX(CASE WHEN sp.created>fp.first_payment_date AND sp.created<=DATEADD('day',45,fp.first_payment_date) AND sp.amounttotransfer>0 THEN 1 ELSE 0 END) AS retained_p1,
    MAX(CASE WHEN sp.created>DATEADD('day',45,fp.first_payment_date) AND sp.created<=DATEADD('day',90,fp.first_payment_date) AND sp.amounttotransfer>0 THEN 1 ELSE 0 END) AS retained_p2
  FROM first_payment fp JOIN fivetran_database.analytics.stripe_payments sp ON fp.lease_id=sp.lease_id
  GROUP BY 1
)
SELECT cd.LeaseActivationMonth, cd.cohort_status,
  COUNT(cd.lease_id) AS total_new_active_leases,
  COUNT(CASE WHEN cd.is_portal_active=1 THEN 1 END) AS portal_active_leases,
  COUNT(fpc.lease_id) AS converted_leases,
  COUNT(fp.lease_id) AS retention_base,
  COUNT(CASE WHEN rc.retained_p1=1 THEN 1 END) AS retained_p1_count,
  COUNT(CASE WHEN rc.retained_p2=1 THEN 1 END) AS retained_p2_count,
  DIV0(COUNT(CASE WHEN rc.retained_p1=1 THEN 1 END), COUNT(fp.lease_id))*100 AS retention_rate_p1,
  DIV0(COUNT(CASE WHEN rc.retained_p2=1 THEN 1 END), COUNT(fp.lease_id))*100 AS retention_rate_p2,
  DIV0(COUNT(CASE WHEN rc.retained_p1=1 AND rc.retained_p2=1 THEN 1 END), COUNT(fp.lease_id))*100 AS habit_rate,
  COUNT(CASE WHEN cd.is_invite_sent=1 THEN 1 END) AS invites_sent
FROM cohort_data cd
LEFT JOIN first_payment_conversion fpc ON cd.lease_id=fpc.lease_id
LEFT JOIN first_payment fp ON cd.lease_id=fp.lease_id
LEFT JOIN retention_check rc ON cd.lease_id=rc.lease_id
GROUP BY 1,2 ORDER BY 1,2;
