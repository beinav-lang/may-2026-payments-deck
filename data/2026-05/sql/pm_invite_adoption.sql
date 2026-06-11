WITH active_pm AS (
  SELECT DISTINCT TO_CHAR(DATE_TRUNC('month', snapshot_date),'YYYY-MM') AS mo, dbtenant
  FROM fivetran_database.analytics.leases_daily_snapshot
  WHERE status='ACTIVE' AND merchant_account_flag=1
    AND snapshot_date BETWEEN '2025-09-01' AND '2026-05-31'
),
invite_pm AS (
  SELECT DISTINCT TO_CHAR(DATE_TRUNC('month', "timestamp"::date),'YYYY-MM') AS mo,
    "properties":"dbTenant"::string AS dbtenant
  FROM posthog_db.events.events_doorloop
  WHERE "event"='invitation_sent' AND "timestamp">='2025-09-01' AND "timestamp"<'2026-06-01'
    AND "properties":"env"='production' AND "properties":"isTestUser"='false'
    AND "properties":"event_source"='Product' AND "properties":"sentToType"='TENANT'
)
SELECT a.mo,
  COUNT(DISTINCT a.dbtenant) AS active_pms,
  COUNT(DISTINCT i.dbtenant) AS pms_invited,
  ROUND(100.0*COUNT(DISTINCT i.dbtenant)/COUNT(DISTINCT a.dbtenant),1) AS pct_invited
FROM active_pm a
LEFT JOIN invite_pm i ON a.mo=i.mo AND a.dbtenant=i.dbtenant
GROUP BY a.mo ORDER BY a.mo;
