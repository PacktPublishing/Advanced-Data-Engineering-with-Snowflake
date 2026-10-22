-- =========================================================================
-- chapter9_pipeline.sql
-- Chapter 9, Section 4.2: End-to-end TechFlow pipeline topology
-- =========================================================================
-- Assembles the three cooperating layers described in Section 4.2:
--
--   1. Reactive ingestion edge  — stream + triggered task writes into a
--      streaming-only table (transactions_clean) within seconds of arrival.
--   2. Transformation core      — Dynamic Table chain reads the VARIANT
--      landing table and maintains cleansed + aggregated views on a lag.
--   3. Operational layer        — scheduled task graph reconciles late
--      corrections nightly, with a finalizer that logs every run.
--
-- Design rule: one writer per table. The triggered task owns
-- transactions_clean. The Dynamic Tables own their own *_dt tables.
-- The scheduled graph owns merchant_daily_revenue.
--
-- Prereqs: run chapter9_setup.sql first.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- =====================================================================
-- Layer 1: Reactive ingestion edge
-- =====================================================================

-- Stream on the VARIANT landing table
CREATE OR REPLACE STREAM raw_db.streaming.new_txn_stream
    ON TABLE raw_db.streaming.raw_transactions
    APPEND_ONLY = TRUE
    SHOW_INITIAL_ROWS = FALSE;

-- Triggered task: fires only when the stream has data. Lives in
-- ops_db.pipelines with the rest of the orchestration; references the
-- stream in raw_db.streaming with its fully qualified name.
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

ALTER TASK ops_db.pipelines.process_new_transactions RESUME;

-- =====================================================================
-- Layer 2: Transformation core (Dynamic Table chain)
-- =====================================================================

-- Silver cleansing DT — reads the VARIANT landing table directly.
-- TRY_TO_DECIMAL / TRY_TO_TIMESTAMP_NTZ guard the all-or-nothing refresh
-- against bad landing values (a single 'N/A' amount would otherwise fail it).
CREATE OR REPLACE DYNAMIC TABLE silver_db.transactions.transactions_clean_dt
    TARGET_LAG = 'DOWNSTREAM'
    WAREHOUSE = BOOK_WH
    REFRESH_MODE = INCREMENTAL
    AS
    SELECT
        raw_data:transaction_id::STRING                  AS transaction_id,
        UPPER(raw_data:merchant.id::STRING)              AS merchant_id,
        UPPER(raw_data:currency::STRING)                 AS currency,
        TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2)   AS amount,
        TRY_TO_TIMESTAMP_NTZ(raw_data:timestamp::STRING) AS transaction_ts,
        raw_data:status::STRING                          AS status
    FROM raw_db.streaming.raw_transactions;

-- Gold aggregation DT — downstream of the cleansing DT
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

-- =====================================================================
-- Layer 3: Operational layer (scheduled task graph)
-- =====================================================================

-- Root: nightly reconciliation of late-arriving corrections. Every task in
-- a graph must share one schema, so the graph lives in ops_db.pipelines and
-- writes cross-database with fully qualified names.
CREATE OR REPLACE TASK ops_db.pipelines.load_transactions_clean
    WAREHOUSE = BOOK_WH
    SCHEDULE = 'USING CRON 0 2 * * * America/New_York'
    TASK_AUTO_RETRY_ATTEMPTS = 2
    SUSPEND_TASK_AFTER_NUM_FAILURES = 3
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

-- Child: daily merchant revenue aggregate
CREATE OR REPLACE TASK ops_db.pipelines.build_daily_revenue
    WAREHOUSE = BOOK_WH
    AFTER ops_db.pipelines.load_transactions_clean
    AS
    INSERT OVERWRITE INTO gold_db.transactions.merchant_daily_revenue
    SELECT
        merchant_id,
        DATE_TRUNC('day', transaction_ts)  AS revenue_date,
        COUNT(*)                           AS transaction_count,
        SUM(amount)                        AS gross_revenue
    FROM silver_db.transactions.transactions_clean
    WHERE status = 'COMPLETED'
    GROUP BY merchant_id, DATE_TRUNC('day', transaction_ts);

-- Finalizer: logs every run
CREATE OR REPLACE TASK ops_db.pipelines.pipeline_finalizer
    WAREHOUSE = BOOK_WH
    FINALIZE = ops_db.pipelines.load_transactions_clean
    AS
    INSERT INTO ops_db.pipelines.pipeline_run_log
    SELECT
        CURRENT_TIMESTAMP()                                  AS logged_at,
        'transaction_transform'                              AS graph_name,
        (SELECT COUNT(*) FROM TABLE(ops_db.information_schema.task_history(
            scheduled_time_range_start => DATEADD('hour', -2, CURRENT_TIMESTAMP()))
         ) WHERE state = 'FAILED')                           AS failed_task_count;

-- Resume the whole graph
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ops_db.pipelines.load_transactions_clean');
