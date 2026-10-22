-- =========================================================================
-- Chapter 9, Section 3.3: Chaining dynamic tables and tuning lag
-- =========================================================================
-- Creates the gold-layer aggregation Dynamic Table downstream of the
-- cleansing DT, then sets the intermediate table's lag to DOWNSTREAM.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- 3.3a  Gold aggregation Dynamic Table
CREATE OR REPLACE DYNAMIC TABLE gold_db.transactions.merchant_daily_revenue_dt
    TARGET_LAG = '1 hour'
    WAREHOUSE = BOOK_WH
    REFRESH_MODE = INCREMENTAL
    AS
    SELECT
        merchant_id,
        DATE_TRUNC('day', transaction_ts)  AS revenue_date,
        COUNT(*)                           AS transaction_count,
        SUM(amount)                        AS gross_revenue
    FROM silver_db.transactions.transactions_clean_dt
    WHERE status = 'COMPLETED'
    GROUP BY merchant_id, DATE_TRUNC('day', transaction_ts);

-- 3.3b  Tune intermediate lag to DOWNSTREAM
ALTER DYNAMIC TABLE silver_db.transactions.transactions_clean_dt
    SET TARGET_LAG = 'DOWNSTREAM';
