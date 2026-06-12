WITH pay AS (
  SELECT customer_id, je_id, amounttotransfer,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD('month',1,created) ELSE created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments
  WHERE type IN ('charge','payment') AND amounttotransfer>0 AND created::date >= '2024-08-20'
),
cust_cyc AS (SELECT DISTINCT customer_id, cyc FROM pay),
flagged AS (
  SELECT customer_id, cyc, LAG(cyc) OVER (PARTITION BY customer_id ORDER BY cyc) AS prev_cyc FROM cust_cyc
),
react AS (SELECT customer_id, cyc FROM flagged WHERE DATEDIFF('month',prev_cyc,cyc)=2),
exploded AS (
  SELECT je._id AS payment_id, lc.value:"linkedTransaction"::string AS linked_transaction, lc.value:"amount"::number AS amount
  FROM airbyte_database.doorloop.journalentries je, LATERAL FLATTEN(input => je.leasepayment:"linkedCharges") lc
  WHERE je.type='leasePayment' AND je.deleted='false' AND je.transactiondate >= '2024-08-01'
),
enriched AS (
  SELECT ec.payment_id, ec.amount AS charge_amount,
    DATE_TRUNC('month', TRY_TO_DATE(jc.transactiondate)) AS charge_due_month
  FROM exploded ec LEFT JOIN airbyte_database.doorloop.journalentries jc ON jc._id=ec.linked_transaction
  WHERE jc.deleted='false'
),
joined AS (
  SELECT r.cyc, DATEDIFF('month', r.cyc, en.charge_due_month) AS off_m, en.charge_amount AS amt
  FROM react r JOIN pay p ON p.customer_id=r.customer_id AND p.cyc=r.cyc
  JOIN enriched en ON en.payment_id=p.je_id
)
SELECT TO_CHAR(cyc,'YYYY-MM') cycle,
  ROUND(SUM(amt)/1e6,2) AS react_chg_m,
  ROUND(100.0*SUM(IFF(off_m>=1,amt,0))/NULLIF(SUM(amt),0),1) AS pct_prepay,
  ROUND(100.0*SUM(IFF(off_m=0, amt,0))/NULLIF(SUM(amt),0),1) AS pct_current,
  ROUND(100.0*SUM(IFF(off_m=-1,amt,0))/NULLIF(SUM(amt),0),1) AS pct_prior1,
  ROUND(100.0*SUM(IFF(off_m<=-2,amt,0))/NULLIF(SUM(amt),0),1) AS pct_prior2plus
FROM joined
WHERE cyc BETWEEN '2025-01-01' AND '2026-05-01'
GROUP BY 1 ORDER BY 1;
