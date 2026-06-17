WITH pay AS (
  SELECT p.customer_id, p.je_id, p.type,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD('month',1,p.created) ELSE p.created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments p
  WHERE p.amounttotransfer>0 AND p.type IN ('charge','payment','cash payment') AND p.created::date>='2023-01-01'
),
fc AS (SELECT customer_id, MIN(cyc) AS first_cyc FROM pay GROUP BY 1),
ft AS (
  SELECT p.customer_id, p.cyc, p.je_id, p.type
  FROM pay p JOIN fc ON fc.customer_id=p.customer_id AND fc.first_cyc=p.cyc
  WHERE p.cyc BETWEEN '2025-02-01' AND '2026-05-01'
),
ftc AS (
  SELECT ft.customer_id, ft.cyc,
    MAX(IFF(ft.type='charge',1,0)) AS used_card,
    MAX(je.dbtenant) AS dbtenant
  FROM ft LEFT JOIN airbyte_database.doorloop.journalentries je ON je._id=ft.je_id
  GROUP BY 1,2
),
pm_m AS (SELECT cyc, dbtenant, COUNT(*) ftn, AVG(used_card) cardrate FROM ftc WHERE dbtenant IS NOT NULL GROUP BY 1,2),
joined AS (
  SELECT ftc.cyc, ftc.used_card,
    IFF(pm.cardrate<0.05 AND pm.ftn>=20,1,0) AS in_batch
  FROM ftc LEFT JOIN pm_m pm ON pm.cyc=ftc.cyc AND pm.dbtenant=ftc.dbtenant
)
SELECT TO_CHAR(cyc,'YYYY-MM') mo, COUNT(*) ft_n,
  ROUND(100.0*AVG(used_card),1) all_card,
  ROUND(100.0*SUM(IFF(in_batch=0,used_card,0))/NULLIF(SUM(IFF(in_batch=0,1,0)),0),1) exbatch_card,
  SUM(in_batch) ft_in_batch
FROM joined GROUP BY 1 ORDER BY 1;
