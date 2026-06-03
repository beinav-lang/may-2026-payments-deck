-- Card-first cohort, ANY-method retention
-- Cohort: customers whose FIRST-EVER payment was a card payment (charge) in window
-- Cell: % of cohort who made ANY payment in month M+N (includes switchers to ACH)
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
first_method AS (
    SELECT p.customer_id,
           MIN(p.created)::date AS firstmethoddate,
           DATE_TRUNC('month', MIN(p.created))::date AS firstmethodmonth
    FROM fivetran_database.analytics.stripe_payments p
    JOIN airbyte_database.doorloop.leases l ON p.lease_id = l._id
    WHERE LOWER(p.type) = 'charge'
      AND p.amounttotransfer > 0
      AND l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
      AND p.created::date >= (SELECT start_date FROM params)
      AND p.created::date <  (SELECT end_date   FROM params)
    GROUP BY p.customer_id
),
valid_customers AS (
    SELECT fm.customer_id, fm.firstmethoddate, fm.firstmethodmonth
    FROM first_method fm
    JOIN first_time ft ON fm.customer_id = ft.customer_id
                       AND fm.firstmethodmonth = ft.firstmonth
),
cohort_sizes AS (
    SELECT firstmethodmonth AS cohort_month, COUNT(*) AS cohort_size
    FROM valid_customers GROUP BY firstmethodmonth
),
base AS (
    -- NO type filter here — any subsequent payment counts as retained
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
    FROM base GROUP BY 1, 2
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
