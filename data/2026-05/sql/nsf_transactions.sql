WITH cyc AS (
  SELECT DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD(month,1,created) ELSE created END) AS m
  FROM fivetran_database.analytics.stripe_nsf
  WHERE created::date BETWEEN '2025-01-25' AND '2026-05-24'
),
nsf AS (SELECT m, COUNT(*) AS nsf_txns FROM cyc GROUP BY 1),
ach AS (
  SELECT DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD(month,1,created) ELSE created END) AS m,
         COUNT(*) AS ach_txns
  FROM fivetran_database.analytics.stripe_payments
  WHERE LOWER(type)='payment' AND amounttotransfer>0 AND created::date BETWEEN '2025-01-25' AND '2026-05-24'
  GROUP BY 1
)
SELECT TO_CHAR(nsf.m,'YYYY-MM') AS cycle, nsf.nsf_txns, ach.ach_txns,
       ROUND(100.0*nsf.nsf_txns/ach.ach_txns,2) AS pct_of_ach
FROM nsf JOIN ach ON nsf.m=ach.m
ORDER BY 1;
