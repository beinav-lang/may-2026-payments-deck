WITH fp AS (
  SELECT customer_id, amounttotransfer AS amt,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD('month',1,created) ELSE created END) AS cyc,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created) AS rn
  FROM fivetran_database.analytics.stripe_payments
  WHERE amounttotransfer>0 AND type IN ('charge','payment','cash payment') AND created::date>='2023-01-01'
)
SELECT TO_CHAR(cyc,'YYYY-MM') AS cycle, COUNT(*) AS ft_n,
  ROUND(MEDIAN(amt),0) AS median_amt, ROUND(AVG(amt),0) AS mean_amt
FROM fp WHERE rn=1 AND cyc BETWEEN '2025-01-01' AND '2026-05-01'
GROUP BY 1 ORDER BY 1;
