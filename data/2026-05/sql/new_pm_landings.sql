WITH pay AS (
  SELECT je.dbtenant AS pm,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD('month',1,p.created) ELSE p.created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.journalentries je ON je._id = p.je_id
  WHERE p.amounttotransfer>0 AND p.type IN ('charge','payment','cash payment')
    AND p.created::date >= '2022-01-01' AND je.dbtenant IS NOT NULL
),
pmfirst AS (SELECT pm, MIN(cyc) AS first_cyc FROM pay GROUP BY pm)
SELECT TO_CHAR(first_cyc,'YYYY-MM') AS cycle, COUNT(*) AS new_pm_accounts
FROM pmfirst WHERE first_cyc BETWEEN '2024-01-01' AND '2026-05-01'
GROUP BY 1 ORDER BY 1;
