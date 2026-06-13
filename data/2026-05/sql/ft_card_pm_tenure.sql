-- Slide 10: first-time card adoption by PM tenure (Stripe only, NO snapshot).
-- FT payer = customer_id's first-ever Stripe payment. Method: type='charge' = card.
-- PM tenure = months between PM's first Stripe payment and this tenant's first payment; <=2 = Onboarding.
WITH pays AS (
  SELECT p.customer_id, p.type, je.dbtenant AS pm, p.created,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD('month',1,p.created) ELSE p.created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.journalentries je ON je._id = p.je_id
  WHERE p.amounttotransfer>0 AND p.type IN ('charge','payment','cash payment')
    AND p.created::date >= '2023-01-01' AND je.dbtenant IS NOT NULL AND p.customer_id IS NOT NULL
),
ft AS (
  SELECT customer_id, pm, cyc, type FROM (
    SELECT customer_id, pm, cyc, type, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created, pm) rn FROM pays
  ) WHERE rn=1
),
pmfirst AS (SELECT pm, MIN(cyc) AS pm_first FROM pays GROUP BY pm)
SELECT TO_CHAR(f.cyc,'YYYY-MM') AS cycle,
  CASE WHEN DATEDIFF('month', p.pm_first, f.cyc) <= 2 THEN 'Onboarding' ELSE 'Mature' END AS pm_cohort,
  COUNT(*) AS ft_total,
  COUNT(CASE WHEN f.type='charge' THEN 1 END) AS ft_card,
  ROUND(100.0*COUNT(CASE WHEN f.type='charge' THEN 1 END)/NULLIF(COUNT(*),0),2) AS pct_card
FROM ft f JOIN pmfirst p ON f.pm = p.pm
WHERE f.cyc BETWEEN '2025-01-01' AND '2026-05-01'
GROUP BY 1,2 ORDER BY 1,2;
