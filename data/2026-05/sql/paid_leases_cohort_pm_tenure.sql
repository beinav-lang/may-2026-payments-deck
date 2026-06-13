-- Slide 8: paid-leases retention cohort, split by PM tenure (Stripe, NO snapshot for the SPLIT).
-- Cohort = leases first-active in the payments-month (snapshot, MA flag, monthly+ freq), Sep '25 -> May '26.
-- cohort_status = PM tenure at activation (months since PM's first Stripe payment <=2 => Onboarding).
-- % paid at offset M0..M7 = distinct leases with a Stripe payment that many cycles after activation.
WITH new_leases AS (
  SELECT lease_id FROM fivetran_database.analytics.leases_daily_snapshot
  GROUP BY lease_id HAVING MIN(snapshot_date) >= '2025-09-01'
),
pm_first AS (
  SELECT je.dbtenant AS pm,
    MIN(DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM p.created)>=25 THEN DATEADD('month',1,p.created) ELSE p.created END)) AS pm_first_cycle
  FROM fivetran_database.analytics.stripe_payments p
  JOIN airbyte_database.doorloop.journalentries je ON je._id = p.je_id
  WHERE p.amounttotransfer>0 AND p.type IN ('charge','payment','cash payment') AND je.dbtenant IS NOT NULL
  GROUP BY 1
),
la AS (
  SELECT lease_id, LeaseActivationMonth,
    CASE WHEN pm_first_cycle IS NULL OR DATEDIFF('month', pm_first_cycle, LeaseActivationMonth) <= 2 THEN 'Onboarding' ELSE 'Mature' END AS cohort_status
  FROM (
    SELECT lds.lease_id, pmf.pm_first_cycle,
      DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM lds.snapshot_date)>=25 THEN DATEADD(month,1,lds.snapshot_date) ELSE lds.snapshot_date END) AS LeaseActivationMonth,
      ROW_NUMBER() OVER (PARTITION BY lds.lease_id ORDER BY lds.snapshot_date) AS rn
    FROM fivetran_database.analytics.leases_daily_snapshot lds
    INNER JOIN new_leases nl ON lds.lease_id = nl.lease_id
    LEFT JOIN pm_first pmf ON lds.dbtenant = pmf.pm
    WHERE lds.status='ACTIVE' AND lds.snapshot_date BETWEEN '2025-09-01' AND '2026-05-24'
      AND lds.rent_frequency IN ('Monthly','Every2Weeks','Weekly','Daily') AND lds.merchant_account_flag=1
  ) WHERE rn=1 AND LeaseActivationMonth BETWEEN '2025-09-01' AND '2026-05-01'
),
lp AS (
  SELECT DISTINCT sp.lease_id::string AS lease_id,
    DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM sp.created)>=25 THEN DATEADD(month,1,sp.created) ELSE sp.created END) AS pay_cycle
  FROM fivetran_database.analytics.stripe_payments sp
  WHERE sp.amounttotransfer>0 AND sp.type IN ('charge','payment','cash payment') AND sp.lease_id IS NOT NULL
)
SELECT TO_CHAR(la.LeaseActivationMonth,'YYYY-MM') AS cohort, la.cohort_status,
  COUNT(DISTINCT la.lease_id) AS sz,
  COUNT(DISTINCT CASE WHEN DATEDIFF('month',la.LeaseActivationMonth,lp.pay_cycle)=0 THEN la.lease_id END) AS m0,
  COUNT(DISTINCT CASE WHEN DATEDIFF('month',la.LeaseActivationMonth,lp.pay_cycle)=1 THEN la.lease_id END) AS m1,
  COUNT(DISTINCT CASE WHEN DATEDIFF('month',la.LeaseActivationMonth,lp.pay_cycle)=2 THEN la.lease_id END) AS m2,
  COUNT(DISTINCT CASE WHEN DATEDIFF('month',la.LeaseActivationMonth,lp.pay_cycle)=3 THEN la.lease_id END) AS m3,
  COUNT(DISTINCT CASE WHEN DATEDIFF('month',la.LeaseActivationMonth,lp.pay_cycle)=4 THEN la.lease_id END) AS m4,
  COUNT(DISTINCT CASE WHEN DATEDIFF('month',la.LeaseActivationMonth,lp.pay_cycle)=5 THEN la.lease_id END) AS m5,
  COUNT(DISTINCT CASE WHEN DATEDIFF('month',la.LeaseActivationMonth,lp.pay_cycle)=6 THEN la.lease_id END) AS m6,
  COUNT(DISTINCT CASE WHEN DATEDIFF('month',la.LeaseActivationMonth,lp.pay_cycle)=7 THEN la.lease_id END) AS m7
FROM la LEFT JOIN lp ON la.lease_id = lp.lease_id AND lp.pay_cycle >= la.LeaseActivationMonth
GROUP BY 1,2 ORDER BY 1,2;
