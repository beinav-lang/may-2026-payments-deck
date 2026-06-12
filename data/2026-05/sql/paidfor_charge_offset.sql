WITH stripe_txns AS (
    SELECT id AS stripe_txn_id, je_id, created, amounttotransfer,
        DATE_TRUNC('month', CASE WHEN EXTRACT(DAY FROM created) >= 25
                                 THEN DATEADD('month',1,created) ELSE created END) AS cycle_month
    FROM fivetran_database.analytics.stripe_payments
    WHERE type IN ('charge','payment') AND amounttotransfer > 0
      AND created::date >= '2024-10-20'
),
exploded_charges AS (
    SELECT je._id AS payment_id,
        lc.value:"linkedTransaction"::string AS linked_transaction,
        lc.value:"amount"::number AS amount
    FROM airbyte_database.doorloop.journalentries je,
         LATERAL FLATTEN(input => je.leasepayment:"linkedCharges") lc
    WHERE je.type = 'leasePayment' AND je.deleted = 'false'
      AND je.transactiondate >= '2024-10-01'
),
enriched AS (
    SELECT ec.payment_id, ec.amount AS charge_amount,
        SUM(ec.amount) OVER (PARTITION BY ec.payment_id) AS total_charge_amount,
        DATE_TRUNC('month', TRY_TO_DATE(je_charge.transactiondate)) AS charge_due_month
    FROM exploded_charges ec
    LEFT JOIN airbyte_database.doorloop.journalentries je_charge ON je_charge._id = ec.linked_transaction
    LEFT JOIN fivetran_database.salesforce.account acc_sf ON je_charge.dbtenant = acc_sf.app_db_tenant_id_c
    WHERE je_charge.deleted = 'false' AND acc_sf.test_account_fivetran_c = 'FALSE'
),
base AS (
    SELECT st.cycle_month,
        DATEDIFF('month', st.cycle_month, en.charge_due_month) AS off_m,
        st.amounttotransfer * (en.charge_amount / NULLIF(en.total_charge_amount,0)) AS amt
    FROM enriched en JOIN stripe_txns st ON st.je_id = en.payment_id
)
SELECT TO_CHAR(cycle_month,'YYYY-MM') AS cycle,
  ROUND(SUM(amt)/1e6,2) AS alloc_m,
  ROUND(100.0*SUM(IFF(off_m>=1,amt,0))/NULLIF(SUM(amt),0),1) AS pct_prepay,
  ROUND(100.0*SUM(IFF(off_m=0, amt,0))/NULLIF(SUM(amt),0),1) AS pct_current,
  ROUND(100.0*SUM(IFF(off_m=-1,amt,0))/NULLIF(SUM(amt),0),1) AS pct_prior1,
  ROUND(100.0*SUM(IFF(off_m=-2,amt,0))/NULLIF(SUM(amt),0),1) AS pct_prior2,
  ROUND(100.0*SUM(IFF(off_m<=-3,amt,0))/NULLIF(SUM(amt),0),1) AS pct_prior3plus
FROM base
WHERE cycle_month BETWEEN '2024-11-01' AND '2026-05-01'
GROUP BY 1 ORDER BY 1;
