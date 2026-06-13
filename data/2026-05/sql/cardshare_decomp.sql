WITH base AS (
  SELECT customer_id, amounttotransfer AS amt, type,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD('month',1,created) ELSE created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments
  WHERE amounttotransfer>0 AND type IN ('charge','payment','cash payment')
    AND created::date >= '2023-01-01'
),
fc AS (SELECT customer_id, MIN(cyc) AS first_cyc FROM base GROUP BY 1),
lab AS (
  SELECT b.cyc, b.amt, IFF(b.type='charge', b.amt, 0) AS card_amt,
    IFF(b.cyc=fc.first_cyc,'FT','RET') AS seg
  FROM base b JOIN fc ON fc.customer_id=b.customer_id
)
SELECT TO_CHAR(cyc,'YYYY-MM') AS cycle,
  ROUND(100.0*SUM(card_amt)/NULLIF(SUM(amt),0),2) AS overall_cardshare,
  ROUND(100.0*SUM(IFF(seg='FT', card_amt,0))/NULLIF(SUM(IFF(seg='FT', amt,0)),0),2) AS ft_cardshare,
  ROUND(100.0*SUM(IFF(seg='RET',card_amt,0))/NULLIF(SUM(IFF(seg='RET',amt,0)),0),2) AS ret_cardshare,
  ROUND(100.0*SUM(IFF(seg='FT', amt,0))/NULLIF(SUM(amt),0),2) AS ft_pct_vol
FROM lab
WHERE cyc BETWEEN '2025-02-01' AND '2026-05-01'
GROUP BY 1 ORDER BY 1;
