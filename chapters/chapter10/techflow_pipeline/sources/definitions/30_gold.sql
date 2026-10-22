-- =====================================================================
-- DCM definitions: gold / analytics layer + daily-revenue task
-- =====================================================================
-- Companion expansion beyond the chapter's silver slice (Section 3.3): the
-- gold Dynamic Table and one suspended daily-revenue task from Chapter 9.
-- The task lives in ops_db.pipelines and writes cross-database with
-- fully qualified names. env_suffix isolates gold tables; {{ wh_name }} is the
-- shared Terraform-owned warehouse, referenced by name via the manifest
-- variable. Fresh tasks arrive suspended unless STARTED appears before AS.
-- =====================================================================

DEFINE DATABASE gold_db{{ env_suffix }};

DEFINE SCHEMA gold_db{{ env_suffix }}.transactions;

DEFINE TABLE gold_db{{ env_suffix }}.transactions.merchant_daily_revenue (
    merchant_id        STRING,
    revenue_date       DATE,
    transaction_count  NUMBER,
    gross_revenue      NUMBER(14,2)
);

DEFINE DYNAMIC TABLE gold_db{{ env_suffix }}.transactions.merchant_daily_revenue_dt
    TARGET_LAG = '1 hour'
    WAREHOUSE = {{ wh_name }}
    REFRESH_MODE = INCREMENTAL
    AS
    SELECT
        merchant_id,
        DATE_TRUNC('day', transaction_ts)  AS revenue_date,
        COUNT(*)                           AS transaction_count,
        SUM(amount)                        AS gross_revenue
    FROM silver_db{{ env_suffix }}.transactions.transactions_clean_dt
    WHERE status = 'COMPLETED'
    GROUP BY merchant_id, DATE_TRUNC('day', transaction_ts);

-- Task (suspended on create). Name carries env_suffix so DEV and PROD do not
-- collide in the shared ops_db.pipelines schema. One writer per table: this
-- task owns merchant_daily_revenue; the Dynamic Table owns *_dt.
DEFINE TASK ops_db.pipelines.build_daily_revenue{{ env_suffix }}
    WAREHOUSE = {{ wh_name }}
    AS
    INSERT OVERWRITE INTO gold_db{{ env_suffix }}.transactions.merchant_daily_revenue
    SELECT
        merchant_id,
        DATE_TRUNC('day', transaction_ts)  AS revenue_date,
        COUNT(*)                           AS transaction_count,
        SUM(amount)                        AS gross_revenue
    FROM silver_db{{ env_suffix }}.transactions.transactions_clean_dt
    WHERE status = 'COMPLETED'
    GROUP BY merchant_id, DATE_TRUNC('day', transaction_ts);
