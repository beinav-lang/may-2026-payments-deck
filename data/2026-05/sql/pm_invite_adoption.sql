WITH acct_start AS (
  SELECT dbtenant, MIN(dbt_first_invoice_date) AS acct_first_invoice
  FROM fivetran_database.analytics.leases_daily_snapshot WHERE merchant_account_flag=1 GROUP BY dbtenant
),
active_pm AS (
  SELECT DISTINCT DATE_TRUNC('month', s.snapshot_date) AS mo, s.dbtenant
  FROM fivetran_database.analytics.leases_daily_snapshot s
  WHERE s.status='ACTIVE' AND s.merchant_account_flag=1 AND s.snapshot_date BETWEEN '2025-09-01' AND '2026-05-31'
),
active_seg AS (
  SELECT a.mo, a.dbtenant,
    CASE WHEN DATEDIFF('day', acct.acct_first_invoice, LAST_DAY(a.mo)) < 90 THEN 'Onboarding' ELSE 'Mature' END AS seg
  FROM active_pm a LEFT JOIN acct_start acct ON a.dbtenant=acct.dbtenant
),
invite_pm AS (
  SELECT DISTINCT DATE_TRUNC('month', "timestamp"::date) AS mo, "properties":"dbTenant"::string AS dbtenant
  FROM posthog_db.events.events_doorloop
  WHERE "event"='invitation_sent' AND "timestamp">='2025-09-01' AND "timestamp"<'2026-06-01'
    AND "properties":"env"='production' AND "properties":"isTestUser"='false'
    AND "properties":"event_source"='Product' AND "properties":"sentToType"='TENANT'
)
SELECT TO_CHAR(a.mo,'YYYY-MM') AS mo, a.seg,
  COUNT(DISTINCT a.dbtenant) AS active_pms,
  COUNT(DISTINCT i.dbtenant) AS invited_pms,
  ROUND(100.0*COUNT(DISTINCT i.dbtenant)/COUNT(DISTINCT a.dbtenant),1) AS pct
FROM active_seg a LEFT JOIN invite_pm i ON a.mo=i.mo AND a.dbtenant=i.dbtenant
GROUP BY 1,2 ORDER BY 1,2;
