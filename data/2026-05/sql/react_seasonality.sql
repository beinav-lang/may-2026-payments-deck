WITH pc AS (
  SELECT DISTINCT p.customer_id,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD(month,1,p.created) ELSE p.created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.leases l ON p.lease_id=l._id
  WHERE p.amounttotransfer>0 AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
    AND p.created::date >= '2023-12-25'
),
fl AS (
  SELECT customer_id, cyc,
    LAG(cyc) OVER (PARTITION BY customer_id ORDER BY cyc) AS prev_cyc,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY cyc) AS rn
  FROM pc
)
SELECT TO_CHAR(cyc,'YYYY-MM') AS cycle, COUNT(*) AS reactivated
FROM fl
WHERE rn>1 AND DATEDIFF('month', prev_cyc, cyc) > 1
  AND cyc BETWEEN '2024-02-01' AND '2026-05-01'
GROUP BY 1 ORDER BY 1;
