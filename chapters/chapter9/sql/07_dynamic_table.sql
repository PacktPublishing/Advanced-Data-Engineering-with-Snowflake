-- =========================================================================
-- Chapter 9, Section 3.1: Creating a dynamic table with a target lag
-- =========================================================================
-- Re-expresses the cleansing step as a Dynamic Table. Snowflake maintains
-- it within the TARGET_LAG of its source automatically. TRY_TO_DECIMAL /
-- TRY_TO_TIMESTAMP_NTZ guard the all-or-nothing refresh against bad values.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- 3.1  Cleansing Dynamic Table
CREATE OR REPLACE DYNAMIC TABLE silver_db.transactions.transactions_clean_dt
    TARGET_LAG = '5 minutes'
    WAREHOUSE = BOOK_WH
    REFRESH_MODE = AUTO
    AS
    SELECT
        raw_data:transaction_id::STRING                  AS transaction_id,
        UPPER(raw_data:merchant.id::STRING)              AS merchant_id,
        UPPER(raw_data:currency::STRING)                 AS currency,
        TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2)   AS amount,
        TRY_TO_TIMESTAMP_NTZ(raw_data:timestamp::STRING) AS transaction_ts,
        raw_data:status::STRING                          AS status
    FROM raw_db.streaming.raw_transactions;

-- Verify first refresh populated the table
SELECT COUNT(*) AS dt_row_count FROM silver_db.transactions.transactions_clean_dt;
