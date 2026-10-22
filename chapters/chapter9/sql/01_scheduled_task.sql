-- =========================================================================
-- Chapter 9, Section 1.1: Creating a scheduled task
-- =========================================================================
-- Creates the nightly cleansing task in the ops_db.pipelines orchestration
-- schema. The task parses the VARIANT landing table into
-- silver_db.transactions.transactions_clean, resumes, fires a single test
-- run, and queries task_history to confirm success.
--
-- Every task in a graph must share one schema, so all tasks live in
-- ops_db.pipelines and write cross-database with fully qualified names.
-- TRY_TO_DECIMAL / TRY_TO_TIMESTAMP_NTZ turn a bad landing value into NULL
-- instead of failing the whole run.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;
SELECT CURRENT_ROLE() AS exercise_role;

-- 1.1  Create the cleansing task (suspended by default)
CREATE OR REPLACE TASK ops_db.pipelines.load_transactions_clean
    WAREHOUSE = BOOK_WH
    SCHEDULE = 'USING CRON 0 2 * * * America/New_York'
    AS
    MERGE INTO silver_db.transactions.transactions_clean AS tgt
    USING (
        SELECT
            raw_data:transaction_id::STRING                  AS transaction_id,
            UPPER(raw_data:merchant.id::STRING)              AS merchant_id,
            UPPER(raw_data:currency::STRING)                 AS currency,
            TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2)   AS amount,
            TRY_TO_TIMESTAMP_NTZ(raw_data:timestamp::STRING) AS transaction_ts,
            raw_data:status::STRING                          AS status
        FROM raw_db.streaming.raw_transactions
        WHERE TRY_TO_TIMESTAMP_NTZ(raw_data:timestamp::STRING)
              >= DATEADD('day', -1, CURRENT_TIMESTAMP())
    ) AS src
    ON tgt.transaction_id = src.transaction_id
    WHEN MATCHED THEN UPDATE SET
        tgt.merchant_id = src.merchant_id,
        tgt.currency = src.currency,
        tgt.amount = src.amount,
        tgt.status = src.status
    WHEN NOT MATCHED THEN INSERT
        (transaction_id, merchant_id, currency, amount, transaction_ts, status)
        VALUES
        (src.transaction_id, src.merchant_id, src.currency, src.amount,
         src.transaction_ts, src.status);

-- Resume and fire a single test run
ALTER TASK ops_db.pipelines.load_transactions_clean RESUME;

EXECUTE TASK ops_db.pipelines.load_transactions_clean;

-- Wait a moment, then check task history
SELECT name, state, scheduled_time, query_start_time, error_message
FROM TABLE(ops_db.information_schema.task_history(
    task_name => 'LOAD_TRANSACTIONS_CLEAN',
    result_limit => 10
))
ORDER BY scheduled_time DESC;
