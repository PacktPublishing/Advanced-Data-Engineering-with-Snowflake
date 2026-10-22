-- =====================================================================
-- chapter9_setup.sql
-- Canonical pipeline objects for Chapters 9, 10, and 11.
--
-- This script is the single source of truth for the transaction pipeline
-- used across the native-orchestration (Ch9), infrastructure-as-code
-- (Ch10), and external-orchestrator (Ch11) chapters. It reuses the
-- medallion databases and naming established in Chapters 1-8:
--   raw_db.streaming  - VARIANT landing layer (Chapter 4)
--   silver_db         - clean, one-row-per-entity integration layer
--   gold_db           - Kimball-style facts and dimensions (Chapter 5)
--   ops_db.pipelines  - dedicated orchestration schema: every task in a
--                       graph must share one schema, so the graph lives here
--                       and its task bodies write cross-database to raw/silver/gold
--   BOOK_WH           - the warehouse used throughout the book
--
-- Run it once if you are starting fresh on the pipeline chapters. It is
-- idempotent: every object is created with IF NOT EXISTS or OR REPLACE,
-- and the landing table is seeded from gold_db.transactions.fact_transactions
-- (built in Chapter 5) with recent timestamps so streams, tasks, and
-- Dynamic Tables have rows to move.
-- =====================================================================

-- Administrator provisioning only. SYSADMIN is the book's default object
-- owner. If earlier exercises used another owner, select that owner here
-- before provisioning; this file does not transfer ownership.
USE ROLE SYSADMIN;
USE SECONDARY ROLES NONE;

-- ---------------------------------------------------------------------
-- Compute: the book-wide warehouse
-- ---------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS BOOK_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE BOOK_WH;

-- ---------------------------------------------------------------------
-- Databases and schemas (created in earlier chapters; ensured here)
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS raw_db;
CREATE DATABASE IF NOT EXISTS silver_db;
CREATE DATABASE IF NOT EXISTS gold_db;
CREATE DATABASE IF NOT EXISTS ops_db;

CREATE SCHEMA IF NOT EXISTS raw_db.streaming;
CREATE SCHEMA IF NOT EXISTS silver_db.transactions;
CREATE SCHEMA IF NOT EXISTS gold_db.transactions;
CREATE SCHEMA IF NOT EXISTS ops_db.pipelines;

-- ---------------------------------------------------------------------
-- Bronze / landing layer: VARIANT table, consistent with Chapter 4.
-- One semi-structured payload per row in the raw_data column. The
-- cleanse step parses it with colon-cast notation, exactly as in
-- Chapter 5, Advanced SQL Transformations.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_db.streaming.raw_transactions (
    raw_data     VARIANT,
    loaded_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

ALTER TABLE raw_db.streaming.raw_transactions SET CHANGE_TRACKING = TRUE;

-- Seed the landing table from the Chapter 5 gold fact, wrapping each row
-- in a JSON payload that includes merchant id and currency (the fields the
-- merchant-revenue pipeline depends on) and a recent timestamp so the
-- nightly window and the streams pick the rows up.
INSERT INTO raw_db.streaming.raw_transactions (raw_data)
SELECT OBJECT_CONSTRUCT(
    'transaction_id', transaction_id,
    'merchant',       OBJECT_CONSTRUCT('id', merchant_id),
    'customer',       OBJECT_CONSTRUCT('id', customer_id),
    'amount',         amount,
    'currency',       currency,
    'timestamp',      DATEADD('hour', UNIFORM(-36, 0, RANDOM()), CURRENT_TIMESTAMP()),
    'status',         status,
    'metadata',       OBJECT_CONSTRUCT('channel', channel, 'risk_score', risk_score)
)
FROM gold_db.transactions.fact_transactions;

-- ---------------------------------------------------------------------
-- Silver layer: cleansed records and a reject quarantine.
-- Columns match the parsed landing payload; currency (not currency_code)
-- aligns with gold_db.transactions.fact_transactions from Chapter 5.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver_db.transactions.transactions_clean (
    transaction_id   STRING        NOT NULL,
    merchant_id      STRING,
    currency         STRING        DEFAULT 'USD',
    amount           NUMBER(12,2),
    transaction_ts   TIMESTAMP_NTZ,
    status           STRING
);

CREATE TABLE IF NOT EXISTS silver_db.transactions.rejected_transactions (
    transaction_id   STRING,
    amount           NUMBER(12,2),
    reject_reason    STRING,
    rejected_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ---------------------------------------------------------------------
-- Gold layer: daily merchant revenue aggregate. fact_transactions itself
-- is created in Chapter 5 and is not redefined here.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold_db.transactions.merchant_daily_revenue (
    merchant_id        STRING,
    revenue_date       DATE,
    transaction_count  NUMBER,
    gross_revenue      NUMBER(14,2)
);

-- ---------------------------------------------------------------------
-- Orchestration layer: audit log written by the graph finalizer, and the
-- stored procedure the Serverless Tasks Flex example calls. Both live in
-- ops_db.pipelines with the task graph, not in the data layers.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ops_db.pipelines.pipeline_run_log (
    logged_at          TIMESTAMP_NTZ,
    graph_name         STRING,
    failed_task_count  NUMBER
);

-- run_cleanse wraps the same idempotent cleanse the scheduled task runs.
-- TRY_TO_DECIMAL / TRY_TO_TIMESTAMP_NTZ turn any bad landing value into a
-- NULL instead of failing the whole run.
CREATE OR REPLACE PROCEDURE ops_db.pipelines.run_cleanse()
    RETURNS STRING
    LANGUAGE SQL
    AS
    $$
    BEGIN
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
            tgt.currency    = src.currency,
            tgt.amount      = src.amount,
            tgt.status      = src.status
        WHEN NOT MATCHED THEN INSERT
            (transaction_id, merchant_id, currency, amount, transaction_ts, status)
            VALUES
            (src.transaction_id, src.merchant_id, src.currency, src.amount,
             src.transaction_ts, src.status);
        RETURN 'cleanse complete';
    END;
    $$;

-- Next run chapter9_admin_setup.sql, then the section scripts as CH09_ORCHESTRATOR.
