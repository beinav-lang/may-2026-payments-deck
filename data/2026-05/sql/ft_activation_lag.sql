WITH fp AS (
  SELECT customer_id, created AS first_pay_date, lease_id FROM (
    SELECT p.customer_id, p.created, p.lease_id,
           ROW_NUMBER() OVER (PARTITION BY p.customer_id ORDER BY p.created, p.lease_id) AS rn
    FROM fivetran_database.analytics.stripe_payments p
    JOIN airbyte_database.doorloop.leases l ON p.lease_id = l._id
    WHERE p.amounttotransfer > 0
      AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
  ) WHERE rn = 1
),
la AS (
  SELECT lease_id, MIN(snapshot_date) AS act_date
  FROM fivetran_database.analytics.leases_daily_snapshot
  WHERE status='ACTIVE' AND merchant_account_flag=1
    AND rent_frequency IN ('Monthly','Every2Weeks','Weekly','Daily')
  GROUP BY lease_id
),
j AS (
  SELECT
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM fp.first_pay_date)>=25 THEN DATEADD(month,1,fp.first_pay_date) ELSE fp.first_pay_date END) AS pay_cycle,
    DATEDIFF('month',
      DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM la.act_date)>=25 THEN DATEADD(month,1,la.act_date) ELSE la.act_date END),
      DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM fp.first_pay_date)>=25 THEN DATEADD(month,1,fp.first_pay_date) ELSE fp.first_pay_date END)) AS lag_m
  FROM fp LEFT JOIN la ON fp.lease_id = la.lease_id
)
SELECT TO_CHAR(pay_cycle,'YYYY-MM') AS cycle,
  CASE WHEN lag_m IS NULL THEN 'unknown' WHEN lag_m<=0 THEN 'M0' WHEN lag_m=1 THEN 'M_1'
       WHEN lag_m=2 THEN 'M_2' WHEN lag_m=3 THEN 'M_3' ELSE 'before' END AS bucket,
  COUNT(*) AS ft
FROM j WHERE pay_cycle BETWEEN '2025-09-01' AND '2026-05-01'
GROUP BY 1,2 ORDER BY 1,2;
