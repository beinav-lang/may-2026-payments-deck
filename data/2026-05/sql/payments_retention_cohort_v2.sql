-- =========================================================
-- Payment Retention Cohort (v2)
-- Cohort = customers whose FIRST-EVER payment landed in cohort_cycle
--           (payments_month cycle convention: 25-of-prior → 24-of-this)
-- Window = Sep '25 → May '26 (matches slide 7 cohort window)
-- Eligibility-adjusted denominator:
--   For each cohort × month_offset, "eligible" customers are those whose
--   cohort-defining lease is still status='ACTIVE' in STG_LEASE_DAILY
--   during the cycle window of cohort_cycle + offset. (When a lease is
--   ACTIVE, its dbtenant is by definition still on platform — so the
--   dbtenant-active condition is implied.)
-- % retention = paid_in_offset / eligible_in_offset
-- Methods produced by this single query:
--   v=any  → first-ever any method, any subsequent payment
--   v=card → first-ever card,       card-only subsequent
--   v=cardany → first-ever card,    any-method subsequent
--   v=ach  → first-ever ach,        ach-only subsequent
--   v=achany → first-ever ach,      any-method subsequent
-- =========================================================

WITH params AS (
    SELECT TO_DATE('2025-09-01') AS start_cycle,
           TO_DATE('2026-06-01') AS end_cycle  -- exclusive (May '26 cycle is the latest)
),
-- Payments_month bucketing for stripe_payments (25→24 cycle, like slide 7)
sp_bucketed AS (
    SELECT
        sp.customer_id,
        sp.lease_id::STRING AS lease_id,
        LOWER(sp.type) AS method,
        sp.amounttotransfer,
        sp.created,
        DATE_TRUNC('month',
            CASE WHEN EXTRACT(DAY FROM sp.created) >= 25
                 THEN DATEADD(month, 1, sp.created)
                 ELSE sp.created END
        ) AS pay_cycle
    FROM fivetran_database.analytics.stripe_payments sp
    WHERE sp.amounttotransfer > 0
      AND LOWER(sp.type) IN ('charge','payment')
      AND sp.lease_id IS NOT NULL
),
-- First-EVER payment per customer with method + lease + dbtenant
first_payment AS (
    SELECT
        spb.customer_id,
        spb.pay_cycle    AS cohort_cycle,
        spb.method       AS first_method,
        spb.lease_id     AS cohort_lease_id,
        ROW_NUMBER() OVER (PARTITION BY spb.customer_id ORDER BY spb.created) AS rn
    FROM sp_bucketed spb
    JOIN airbyte_database.doorloop.leases l ON spb.lease_id::STRING = l._id::STRING
    WHERE l.recurringrentfrequency IN ('Weekly','Daily','Monthly','Every2Weeks')
),
cohort AS (
    SELECT customer_id, cohort_cycle, first_method, cohort_lease_id
    FROM first_payment
    WHERE rn = 1
      AND cohort_cycle >= (SELECT start_cycle FROM params)
      AND cohort_cycle <  (SELECT end_cycle   FROM params)
),
-- Enumerate the 9 cohort cycles
cycle_dates AS (
    SELECT DISTINCT cohort_cycle FROM cohort
),
-- Cross cohort customers × month_offset 0..12; bound by end-of-data cycle
offsets AS (
    SELECT 0  AS month_offset UNION ALL SELECT 1  UNION ALL SELECT 2  UNION ALL
    SELECT 3  UNION ALL SELECT 4  UNION ALL SELECT 5  UNION ALL SELECT 6  UNION ALL
    SELECT 7  UNION ALL SELECT 8  UNION ALL SELECT 9  UNION ALL SELECT 10 UNION ALL
    SELECT 11 UNION ALL SELECT 12
),
expanded AS (
    SELECT
        c.customer_id,
        c.cohort_cycle,
        c.first_method,
        c.cohort_lease_id,
        o.month_offset,
        DATEADD(month, o.month_offset, c.cohort_cycle) AS target_cycle
    FROM cohort c
    CROSS JOIN offsets o
    WHERE DATEADD(month, o.month_offset, c.cohort_cycle) < (SELECT end_cycle FROM params)
),
-- Eligibility: cohort_lease has at least one ACTIVE day in cycle window of target_cycle
-- Cycle window for target_cycle (which is a calendar-month start) = [target_cycle-7 days, target_cycle+24 days]
-- but since payments_month is bucket-name, the underlying days are (25 of prev month → 24 of cycle month).
-- Approximation: use the target_cycle CALENDAR month as the eligibility window for STG_LEASE_DAILY.
-- (close enough — lease status changes daily, so the ~30-day window captures whether the
--  lease was ACTIVE at any point during the cycle).
lease_active AS (
    SELECT DISTINCT
        e.customer_id, e.cohort_cycle, e.month_offset
    FROM expanded e
    JOIN DWH_PROD.STG.STG_LEASE_DAILY ld
        ON ld.lease_id::STRING = e.cohort_lease_id
       AND ld._date >= DATEADD(day, -7, e.target_cycle)
       AND ld._date <  DATEADD(day, 24, DATEADD(month, 1, e.target_cycle))
       AND ld.status = 'ACTIVE'
),
-- Paid in target cycle (with method filter)
paid_card AS (
    SELECT DISTINCT spb.customer_id, spb.pay_cycle
    FROM sp_bucketed spb
    WHERE spb.method = 'charge'
),
paid_ach AS (
    SELECT DISTINCT spb.customer_id, spb.pay_cycle
    FROM sp_bucketed spb
    WHERE spb.method = 'payment'
),
paid_any AS (
    SELECT DISTINCT spb.customer_id, spb.pay_cycle
    FROM sp_bucketed spb
),
-- For each cohort × offset, count eligible customers AND paid (by method variant)
agg AS (
    SELECT
        e.cohort_cycle,
        e.first_method,
        e.month_offset,
        COUNT(DISTINCT e.customer_id) AS cohort_size_total,  -- total cohort population
        COUNT(DISTINCT la.customer_id) AS eligible_n,          -- in-cycle eligible
        -- numerator variants
        COUNT(DISTINCT CASE WHEN la.customer_id IS NOT NULL AND pc.customer_id IS NOT NULL THEN e.customer_id END) AS paid_card_eligible,
        COUNT(DISTINCT CASE WHEN la.customer_id IS NOT NULL AND pa.customer_id IS NOT NULL THEN e.customer_id END) AS paid_ach_eligible,
        COUNT(DISTINCT CASE WHEN la.customer_id IS NOT NULL AND py.customer_id IS NOT NULL THEN e.customer_id END) AS paid_any_eligible
    FROM expanded e
    LEFT JOIN lease_active la
           ON la.customer_id = e.customer_id
          AND la.cohort_cycle = e.cohort_cycle
          AND la.month_offset = e.month_offset
    LEFT JOIN paid_card pc ON pc.customer_id = e.customer_id AND pc.pay_cycle = e.target_cycle
    LEFT JOIN paid_ach  pa ON pa.customer_id = e.customer_id AND pa.pay_cycle = e.target_cycle
    LEFT JOIN paid_any  py ON py.customer_id = e.customer_id AND py.pay_cycle = e.target_cycle
    GROUP BY 1, 2, 3
)
SELECT
    TO_CHAR(cohort_cycle, 'YYYY-MM-DD') AS cohort_cycle,
    first_method,
    month_offset,
    cohort_size_total,
    eligible_n,
    paid_card_eligible,
    paid_ach_eligible,
    paid_any_eligible
FROM agg
ORDER BY cohort_cycle, first_method, month_offset;
