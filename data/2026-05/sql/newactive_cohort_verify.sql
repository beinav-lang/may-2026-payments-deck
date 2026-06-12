WITH la AS (
  SELECT lease_id,
    MIN(snapshot_date) AS first_active_date,
    MIN(dbt_first_invoice_date) AS first_invoice_date
  FROM fivetran_database.analytics.leases_daily_snapshot
  WHERE status='ACTIVE' AND merchant_account_flag=1
    AND rent_frequency IN ('Monthly','Every2Weeks','Weekly','Daily')
  GROUP BY lease_id
),
cyc AS (
  SELECT lease_id,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM first_active_date)>=25 THEN DATEADD(month,1,first_active_date) ELSE first_active_date END) AS act_cycle,
    CASE WHEN DATEDIFF('day', first_invoice_date, first_active_date) < 90 THEN 'Onboarding' ELSE 'Mature' END AS cohort_status
  FROM la
)
SELECT TO_CHAR(act_cycle,'YYYY-MM') AS act_cycle, cohort_status, COUNT(*) AS new_active_leases
FROM cyc WHERE act_cycle IN ('2026-04-01','2026-05-01')
GROUP BY 1,2 ORDER BY 1,2;
