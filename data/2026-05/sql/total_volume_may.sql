WITH pay AS (
  SELECT LOWER(p.type) AS ptype, p.amounttotransfer AS amt, p.lease_id
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.leases l ON p.lease_id = l._id
  WHERE p.amounttotransfer > 0
    AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
    AND p.created::date >= '2026-04-25' AND p.created::date <= '2026-05-24'
)
SELECT COALESCE(ptype,'TOTAL') AS ptype,
       COUNT(*) AS n_payments,
       ROUND(SUM(amt)/1e6, 3) AS vol_m,
       COUNT(DISTINCT lease_id) AS leases
FROM pay
GROUP BY ROLLUP(ptype)
ORDER BY vol_m DESC NULLS LAST;
