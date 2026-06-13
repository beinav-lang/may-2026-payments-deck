WITH pay AS (
  SELECT customer_id, type,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD('month',1,created) ELSE created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments
  WHERE amounttotransfer>0 AND type IN ('charge','payment','cash payment') AND created::date>='2023-01-01'
),
fc AS (SELECT customer_id, MIN(cyc) AS first_cyc FROM pay GROUP BY 1),
ften AS (
  SELECT b.cyc, b.customer_id, MAX(IFF(b.type='charge',1,0)) AS used_card
  FROM pay b JOIN fc ON fc.customer_id=b.customer_id AND fc.first_cyc=b.cyc
  GROUP BY 1,2
)
SELECT TO_CHAR(cyc,'YYYY-MM') AS cycle, COUNT(*) AS ft_n,
  ROUND(100.0*SUM(used_card)/COUNT(*),1) AS ft_card_adoption_pct
FROM ften
WHERE cyc BETWEEN '2025-01-01' AND '2026-05-01'
GROUP BY 1 ORDER BY 1;
