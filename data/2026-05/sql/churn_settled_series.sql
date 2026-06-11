WITH pay AS (
  SELECT DISTINCT p.lease_id,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD(month,1,p.created) ELSE p.created END) AS cyc
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.leases l ON p.lease_id=l._id
  WHERE p.amounttotransfer>0 AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
    AND p.created::date BETWEEN '2025-01-25' AND '2026-05-24'
),
m AS (SELECT lease_id, cyc, DATEADD('month',1,cyc) AS next_cyc FROM pay)
SELECT TO_CHAR(m.next_cyc,'YYYY-MM') AS churn_cycle, COUNT(*) AS churned_settled
FROM m
LEFT JOIN pay p2 ON p2.lease_id=m.lease_id AND p2.cyc=m.next_cyc
WHERE p2.lease_id IS NULL AND m.next_cyc BETWEEN '2025-04-01' AND '2026-05-01'
GROUP BY 1 ORDER BY 1;
