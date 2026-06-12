SELECT TO_CHAR(DATE_TRUNC('month', p.created),'YYYY-MM') AS ym,
  CASE WHEN EXTRACT(DAY FROM p.created) BETWEEN 1 AND 5  THEN 'a_01-05'
       WHEN EXTRACT(DAY FROM p.created) BETWEEN 6 AND 19 THEN 'b_06-19'
       WHEN EXTRACT(DAY FROM p.created) BETWEEN 20 AND 24 THEN 'c_20-24_precutoff'
       ELSE 'd_25-EOM_nextcycle' END AS day_bucket,
  COUNT(*) AS payments
FROM fivetran_database.analytics.stripe_payments p
JOIN airbyte_database.doorloop.leases l ON p.lease_id=l._id
WHERE p.amounttotransfer>0 AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
  AND ( (p.created::date BETWEEN '2025-02-01' AND '2025-04-30')
     OR (p.created::date BETWEEN '2026-02-01' AND '2026-04-30') )
GROUP BY 1,2 ORDER BY 1,2;
