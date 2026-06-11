WITH base AS (
  SELECT p.customer_id, LOWER(p.type) AS ptype, p.amounttotransfer AS amt,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD(month,1,p.created) ELSE p.created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.leases l ON p.lease_id=l._id
  WHERE p.amounttotransfer>0 AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
    AND LOWER(p.type) IN ('charge','payment') AND p.created::date BETWEEN '2026-02-25' AND '2026-05-24'
),
pc AS (SELECT DISTINCT customer_id, cyc FROM base)
SELECT label,
  COUNT(DISTINCT customer_id) AS n,
  ROUND(100.0*SUM(CASE WHEN ptype='charge' THEN amt ELSE 0 END)/SUM(amt),2) AS card_share_pct
FROM (
  SELECT b.customer_id,b.ptype,b.amt,'1 May churners (Apr mix)' label FROM base b WHERE b.cyc='2026-04-01'
    AND NOT EXISTS (SELECT 1 FROM pc WHERE pc.customer_id=b.customer_id AND pc.cyc='2026-05-01')
  UNION ALL
  SELECT b.customer_id,b.ptype,b.amt,'2 Apr churners (Mar mix)' FROM base b WHERE b.cyc='2026-03-01'
    AND NOT EXISTS (SELECT 1 FROM pc WHERE pc.customer_id=b.customer_id AND pc.cyc='2026-04-01')
  UNION ALL
  SELECT b.customer_id,b.ptype,b.amt,'3 Retained Apr->May (baseline)' FROM base b WHERE b.cyc='2026-04-01'
    AND EXISTS (SELECT 1 FROM pc WHERE pc.customer_id=b.customer_id AND pc.cyc='2026-05-01')
) GROUP BY label ORDER BY label;
