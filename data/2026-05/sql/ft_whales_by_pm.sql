WITH base AS (
  SELECT customer_id, je_id, amounttotransfer AS amt, type,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created)>=25 THEN DATEADD('month',1,created) ELSE created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments
  WHERE amounttotransfer>0 AND type IN ('charge','payment','cash payment') AND created::date>='2023-01-01'
),
fc AS (SELECT customer_id, MIN(cyc) AS first_cyc FROM base GROUP BY 1),
ft AS (
  SELECT b.customer_id, b.je_id, b.amt, b.type, b.cyc
  FROM base b JOIN fc ON fc.customer_id=b.customer_id
  WHERE fc.first_cyc=b.cyc AND b.cyc IN ('2026-04-01','2026-05-01')
),
pm AS (
  SELECT ft.cyc, ft.customer_id, ft.amt, ft.type, acc.name AS pm_name
  FROM ft
  LEFT JOIN airbyte_database.doorloop.journalentries je ON je._id=ft.je_id
  LEFT JOIN fivetran_database.salesforce.account acc ON je.dbtenant=acc.app_db_tenant_id_c
)
SELECT TO_CHAR(cyc,'YYYY-MM') AS cycle, COALESCE(pm_name,'(unmapped)') AS pm,
  COUNT(DISTINCT customer_id) AS ft_tenants,
  ROUND(SUM(amt)/1e3,0) AS vol_k,
  ROUND(100.0*SUM(IFF(type='charge',amt,0))/NULLIF(SUM(amt),0),1) AS card_share
FROM pm
GROUP BY 1,2
HAVING COUNT(DISTINCT customer_id) >= 80
ORDER BY cycle, ft_tenants DESC;
