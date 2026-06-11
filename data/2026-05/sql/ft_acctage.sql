WITH fp AS (
  SELECT customer_id, first_pay_date, lease_id FROM (
    SELECT p.customer_id, p.created AS first_pay_date, p.lease_id,
      ROW_NUMBER() OVER (PARTITION BY p.customer_id ORDER BY p.created, p.lease_id) rn
    FROM fivetran_database.analytics.stripe_payments p
    JOIN airbyte_database.doorloop.leases l ON p.lease_id=l._id
    WHERE p.amounttotransfer>0 AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
  ) WHERE rn=1
),
lease_dbt AS (SELECT lease_id, MAX(dbtenant) dbtenant FROM fivetran_database.analytics.leases_daily_snapshot WHERE merchant_account_flag=1 GROUP BY lease_id),
acct_start AS (SELECT dbtenant, MIN(dbt_first_invoice_date) acct_first_invoice FROM fivetran_database.analytics.leases_daily_snapshot WHERE merchant_account_flag=1 GROUP BY dbtenant),
fpc AS (SELECT fp.first_pay_date, a.acct_first_invoice,
  DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM fp.first_pay_date)>=25 THEN DATEADD(month,1,fp.first_pay_date) ELSE fp.first_pay_date END) cyc
  FROM fp LEFT JOIN lease_dbt ld ON fp.lease_id=ld.lease_id LEFT JOIN acct_start a ON ld.dbtenant=a.dbtenant)
SELECT TO_CHAR(cyc,'YYYY-MM') cycle,
  CASE WHEN acct_first_invoice IS NULL THEN 'unknown' WHEN DATEDIFF('day',acct_first_invoice,first_pay_date)<90 THEN 'Onboarding' ELSE 'Mature' END age,
  COUNT(*) ft
FROM fpc WHERE cyc BETWEEN '2025-01-01' AND '2026-05-01' GROUP BY 1,2 ORDER BY 1,2;
