WITH cyc AS (
  SELECT DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD(month,1,created) ELSE created END) AS m, fee
  FROM fivetran_database.analytics.stripe_nsf
  WHERE created::date BETWEEN '2025-01-25' AND '2026-05-24'
)
SELECT TO_CHAR(m,'YYYY-MM') AS cycle,
  COUNT(CASE WHEN fee=0.25 THEN 1 END) AS txn_25,
  COUNT(CASE WHEN fee=0.40 THEN 1 END) AS txn_40,
  COUNT(*) AS total
FROM cyc GROUP BY 1 ORDER BY 1;
