SELECT
  type,
  ROUND(SUM(amounttotransfer)/1e6,1) AS volume_m,
  ROUND(SUM(fee)/1e3,1)             AS fee_k,
  ROUND(100.0*SUM(fee)/NULLIF(SUM(amounttotransfer),0),3) AS eff_fee_pct,
  COUNT(*) AS txns
FROM fivetran_database.analytics.stripe_payments
WHERE amounttotransfer>0 AND type IN ('charge','payment','cash payment')
  AND DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD('month',1,created) ELSE created END) = '2026-05-01'
GROUP BY 1 ORDER BY 1;
