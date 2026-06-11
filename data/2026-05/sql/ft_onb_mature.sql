WITH fp AS (
  SELECT customer_id, first_pay_date, lease_id FROM (
    SELECT p.customer_id, p.created AS first_pay_date, p.lease_id,
           ROW_NUMBER() OVER (PARTITION BY p.customer_id ORDER BY p.created, p.lease_id) rn
    FROM fivetran_database.analytics.stripe_payments p
    JOIN airbyte_database.doorloop.leases l ON p.lease_id = l._id
    WHERE p.amounttotransfer>0 AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
  ) WHERE rn=1
),
la AS (
  SELECT lease_id, MIN(snapshot_date) AS first_active_date, MIN(dbt_first_invoice_date) AS first_invoice_date
  FROM fivetran_database.analytics.leases_daily_snapshot
  WHERE status='ACTIVE' AND merchant_account_flag=1
    AND rent_frequency IN ('Monthly','Every2Weeks','Weekly','Daily')
  GROUP BY lease_id
)
SELECT
  TO_CHAR(DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM fp.first_pay_date)>=25 THEN DATEADD(month,1,fp.first_pay_date) ELSE fp.first_pay_date END),'YYYY-MM') AS cycle,
  CASE WHEN la.lease_id IS NULL THEN 'unknown'
       WHEN DATEDIFF('day', la.first_invoice_date, la.first_active_date) < 90 THEN 'Onboarding'
       ELSE 'Mature' END AS cohort_status,
  COUNT(*) AS ft
FROM fp LEFT JOIN la ON fp.lease_id = la.lease_id
WHERE DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM fp.first_pay_date)>=25 THEN DATEADD(month,1,fp.first_pay_date) ELSE fp.first_pay_date END) BETWEEN '2025-09-01' AND '2026-05-01'
GROUP BY 1,2 ORDER BY 1,2;
