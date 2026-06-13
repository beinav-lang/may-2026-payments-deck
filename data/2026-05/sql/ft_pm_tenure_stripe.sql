-- CANONICAL: first-time tenant payers (Stripe only) split by their PM's tenure.
-- PM tenure = months between the PM's FIRST-EVER Stripe payment and the tenant's first payment.
-- No leases_daily_snapshot. PM = je.dbtenant. Tenant payer = stripe customer_id.
WITH pays AS (
  SELECT p.customer_id, je.dbtenant AS pm,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD('month',1,p.created) ELSE p.created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.journalentries je ON je._id = p.je_id
  WHERE p.amounttotransfer>0 AND p.type IN ('charge','payment','cash payment')
    AND p.created::date >= '2023-01-01' AND je.dbtenant IS NOT NULL AND p.customer_id IS NOT NULL
),
ftpay AS (  -- each tenant's FIRST-ever payment (cycle + the PM it was on)
  SELECT customer_id, pm, cyc FROM (
    SELECT customer_id, pm, cyc, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY cyc, pm) rn FROM pays
  ) WHERE rn=1
),
pmfirst AS ( SELECT pm, MIN(cyc) AS pm_first FROM pays GROUP BY pm )
SELECT TO_CHAR(f.cyc,'YYYY-MM') AS cycle,
  CASE WHEN DATEDIFF('month', p.pm_first, f.cyc) <= 2 THEN 'Onboarding_0_2mo' ELSE 'Mature_3plus' END AS pm_cohort,
  COUNT(*) AS ft_tenants
FROM ftpay f JOIN pmfirst p ON f.pm = p.pm
WHERE f.cyc BETWEEN '2025-01-01' AND '2026-05-01'
GROUP BY 1,2 ORDER BY 1,2;
