-- Any-method first payment cohort retention
-- Cohort: customers whose FIRST-EVER payment occurred in the cohort month (any method)
-- Cell: % of cohort who made any payment in month M+N
-- NOTE: first_time has NO date filter — captures first-EVER payment per customer.
--   valid_customers then keeps only customers whose first-ever falls inside the window.
WITH params AS (
    SELECT TO_DATE('2025-01-01') AS start_date,
           TO_DATE('2026-06-01') AS end_date
),
first_time AS (
    SELECT p.customer_id,
           MIN(p.created)::date AS firstdate,
           DATE_TRUNC('month', MIN(p.created))::date AS firstmonth
    FROM fivetran_database.analytics.stripe_payments p
    JOIN airbyte_database.doorloop.leases l ON p.lease_id = l._id
    WHERE p.amounttotransfer > 0
      AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
    GROUP BY p.customer_id
),
valid_customers AS (
    SELECT customer_id, firstdate AS firstmethoddate, firstmonth AS firstmethodmonth
    FROM first_time
    WHERE firstdate >= (SELECT start_date FROM params)
      AND firstdate <  (SELECT end_date   FROM params)
),
cohort_sizes AS (
    SELECT firstmethodmonth AS cohort_month, COUNT(*) AS cohort_size
    FROM valid_customers
    GROUP BY firstmethodmonth
),
base AS (
    SELECT vc.firstmethodmonth AS cohort_month,
           DATEDIFF('month', vc.firstmethoddate, p.created) AS month_offset,
           p.customer_id
    FROM fivetran_database.analytics.stripe_payments p
    JOIN valid_customers vc ON p.customer_id = vc.customer_id
    JOIN airbyte_database.doorloop.leases l ON p.lease_id = l._id
    WHERE p.amounttotransfer > 0
      AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
      AND p.created::date >= (SELECT start_date FROM params)
      AND p.created::date <  (SELECT end_date FROM params)
      AND DATEDIFF('month', vc.firstmethoddate, p.created) BETWEEN 0 AND 12
),
cohort_counts AS (
    SELECT cohort_month, month_offset, COUNT(DISTINCT customer_id) AS customers
    FROM base
    GROUP BY 1, 2
)
SELECT cs.cohort_month, cs.cohort_size,
       MAX(CASE WHEN cc.month_offset =  0 THEN cc.customers END) AS m0,
       MAX(CASE WHEN cc.month_offset =  1 THEN cc.customers END) AS m1,
       MAX(CASE WHEN cc.month_offset =  2 THEN cc.customers END) AS m2,
       MAX(CASE WHEN cc.month_offset =  3 THEN cc.customers END) AS m3,
       MAX(CASE WHEN cc.month_offset =  4 THEN cc.customers END) AS m4,
       MAX(CASE WHEN cc.month_offset =  5 THEN cc.customers END) AS m5,
       MAX(CASE WHEN cc.month_offset =  6 THEN cc.customers END) AS m6,
       MAX(CASE WHEN cc.month_offset =  7 THEN cc.customers END) AS m7,
       MAX(CASE WHEN cc.month_offset =  8 THEN cc.customers END) AS m8,
       MAX(CASE WHEN cc.month_offset =  9 THEN cc.customers END) AS m9,
       MAX(CASE WHEN cc.month_offset = 10 THEN cc.customers END) AS m10,
       MAX(CASE WHEN cc.month_offset = 11 THEN cc.customers END) AS m11,
       MAX(CASE WHEN cc.month_offset = 12 THEN cc.customers END) AS m12
FROM cohort_sizes cs
LEFT JOIN cohort_counts cc ON cc.cohort_month = cs.cohort_month
GROUP BY cs.cohort_month, cs.cohort_size
ORDER BY cs.cohort_month;
