-- =========================================================================
-- Chapter 9, Section 2.2: Running work only when data arrives
-- =========================================================================
-- Creates a triggered task that fires only when the stream has data,
-- merging new raw transactions into the silver layer. The task lives in
-- ops_db.pipelines with the rest of the orchestration; the WHEN clause and
-- body reference the stream in raw_db.streaming with its fully qualified name.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- 2.2  Triggered task with WHEN guard
CREATE OR REPLACE TASK ops_db.pipelines.process_new_transactions
    WAREHOUSE = BOOK_WH
    WHEN SYSTEM$STREAM_HAS_DATA('raw_db.streaming.new_txn_stream')
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
        FROM raw_db.streaming.new_txn_stream
        WHERE METADATA$ACTION = 'INSERT'
    ) AS src
    ON tgt.transaction_id = src.transaction_id
    WHEN NOT MATCHED THEN INSERT
        (transaction_id, merchant_id, currency, amount, transaction_ts, status)
        VALUES
        (src.transaction_id, src.merchant_id, src.currency,
         src.amount, src.transaction_ts, src.status);

-- Resume the triggered task
ALTER TASK ops_db.pipelines.process_new_transactions RESUME;
