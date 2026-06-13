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
ftpm AS (
  SELECT ft.cyc, ft.customer_id, ft.amt, ft.type, acc.name AS pm
  FROM ft
  LEFT JOIN airbyte_database.doorloop.journalentries je ON je._id=ft.je_id
  LEFT JOIN fivetran_database.salesforce.account acc ON je.dbtenant=acc.app_db_tenant_id_c
),
tenant AS (
  SELECT cyc, customer_id, MAX(pm) AS pm,
    SUM(amt) AS amt, SUM(IFF(type='charge',amt,0)) AS card_amt,
    MAX(IFF(type='charge',1,0)) AS used_card
  FROM ftpm GROUP BY 1,2
)
SELECT TO_CHAR(cyc,'YYYY-MM') AS cycle, COUNT(*) AS ft_n,
  ROUND(100.0*SUM(used_card)/COUNT(*),2) AS adopt_all,
  ROUND(100.0*SUM(IFF(NOT COALESCE(pm,'') ILIKE 'Costello%',used_card,0))/NULLIF(SUM(IFF(NOT COALESCE(pm,'') ILIKE 'Costello%',1,0)),0),2) AS adopt_x_costello,
  ROUND(100.0*SUM(IFF(NOT COALESCE(pm,'') ILIKE 'Christian Relief%',used_card,0))/NULLIF(SUM(IFF(NOT COALESCE(pm,'') ILIKE 'Christian Relief%',1,0)),0),2) AS adopt_x_cr,
  ROUND(100.0*SUM(card_amt)/NULLIF(SUM(amt),0),2) AS dshare_all,
  ROUND(100.0*SUM(IFF(NOT COALESCE(pm,'') ILIKE 'Costello%',card_amt,0))/NULLIF(SUM(IFF(NOT COALESCE(pm,'') ILIKE 'Costello%',amt,0)),0),2) AS dshare_x_costello,
  ROUND(100.0*SUM(IFF(NOT COALESCE(pm,'') ILIKE 'Christian Relief%',card_amt,0))/NULLIF(SUM(IFF(NOT COALESCE(pm,'') ILIKE 'Christian Relief%',amt,0)),0),2) AS dshare_x_cr
FROM tenant GROUP BY 1 ORDER BY 1;
