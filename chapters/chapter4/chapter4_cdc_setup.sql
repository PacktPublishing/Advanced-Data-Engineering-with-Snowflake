-- =============================================================================
-- Chapter 4: Real-Time Ingestion and Change Data Capture
-- CDC SETUP -- Section 5 (Streams, the MERGE pattern, Dynamic Tables, and
-- schema evolution).
--
-- Independent of chapter4_kafka_setup.sql and chapter4_openflow_setup.sql.
--
-- Prerequisites:
--   - setup/snowflake_setup.sql executed (BOOK_WH, role blocks)
--   - RAW_DB and SILVER_DB (created below with IF NOT EXISTS; Chapters 2-3
--     create them too, so re-running is safe)
--
-- Placeholders: search for <REPLACE: ...> and substitute with your values.
-- Role convention (per the book): USERADMIN creates roles, SYSADMIN owns
-- databases/schemas/tables and object grants, ACCOUNTADMIN only where an
-- account-level privilege requires it (integrations, account grants).
-- =============================================================================

-- Databases and schemas used by the CDC labs. IF NOT EXISTS makes this file
-- runnable standalone even if Chapters 2-3 were skipped.
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS RAW_DB;
CREATE DATABASE IF NOT EXISTS SILVER_DB;
CREATE SCHEMA IF NOT EXISTS RAW_DB.LANDING;
CREATE SCHEMA IF NOT EXISTS RAW_DB.CDC;
USE WAREHOUSE BOOK_WH;
USE DATABASE RAW_DB;

-- =============================================================================
-- Section 5.1: Snowflake Streams — The Foundation of Native CDC
-- =============================================================================

USE SCHEMA CDC;

-- Create a sample customers landing table (if not already present)
CREATE TABLE IF NOT EXISTS RAW_DB.LANDING.customers (
    customer_id STRING,
    name STRING,
    email STRING,
    status STRING,
    created_at TIMESTAMP_NTZ,
    updated_at TIMESTAMP_NTZ,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Create a stream on the raw landing table
CREATE OR REPLACE STREAM RAW_DB.CDC.customer_changes
    ON TABLE RAW_DB.LANDING.customers
    APPEND_ONLY = FALSE
    SHOW_INITIAL_ROWS = TRUE;

-- Query the stream to see changes since last consumption
SELECT
    METADATA$ACTION,     -- INSERT, DELETE
    METADATA$ISUPDATE,   -- TRUE for both rows of an update pair
    METADATA$ROW_ID,     -- Unique row identifier
    *
FROM RAW_DB.CDC.customer_changes;

-- Set data retention to at least seven days on the source table so the stream
-- stays consumable through normal operational pauses. Missing the retention
-- window forces stream recreation (losing unconsumed changes) or full reload.
ALTER TABLE RAW_DB.LANDING.customers SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- Alert that fires when the stream is sitting on unconsumed changes. Neither
-- ACCOUNT_USAGE nor INFORMATION_SCHEMA has a STREAMS view, so the check uses
-- SYSTEM$STREAM_HAS_DATA: the merge task below runs every 5 minutes, so
-- unconsumed data at the top of the hour means the consumer has stalled --
-- well before the retention window closes.
CREATE OR REPLACE ALERT RAW_DB.CDC.stream_staleness_alert
    WAREHOUSE = BOOK_WH
    SCHEDULE = '60 MINUTE'
    IF (EXISTS (
        SELECT 1
        WHERE SYSTEM$STREAM_HAS_DATA('RAW_DB.CDC.CUSTOMER_CHANGES')
    ))
    THEN CALL SYSTEM$SEND_EMAIL(
        'data_ops',
        'ops@techflow.com',  -- <REPLACE: your ops email>
        'Stream consumption alert',
        'CUSTOMER_CHANGES has unconsumed data; the CDC task may be stalled'
    );

ALTER ALERT RAW_DB.CDC.stream_staleness_alert RESUME;

-- Verify the stream is registered. There is no INFORMATION_SCHEMA.STREAMS
-- view; use SHOW and read the output through RESULT_SCAN.
SHOW STREAMS IN SCHEMA RAW_DB.CDC;

SELECT "name", "mode", "owner", "created_on", "stale"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));



-- =============================================================================
-- Section 5.2: The CDC Merge Pattern
-- =============================================================================

USE DATABASE SILVER_DB;  -- the book's standard silver-layer database
CREATE SCHEMA IF NOT EXISTS CUSTOMERS;
USE SCHEMA CUSTOMERS;

-- Create the silver-layer target table. Per the medallion convention used in
-- the book, silver holds clean per-entity records (singular noun: `customer`).
-- The gold layer in Chapter 5 denormalizes this into Kimball-style
-- `dim_customers`. Audit columns trace any row back to the change event that
-- produced it.
CREATE OR REPLACE TABLE SILVER_DB.CUSTOMERS.customer (
    customer_id STRING PRIMARY KEY,
    name STRING,
    email STRING,
    status STRING,
    created_at TIMESTAMP_NTZ,
    updated_at TIMESTAMP_NTZ,
    _cdc_action STRING,
    _cdc_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- The two MERGE statements below MUST run inside one explicit transaction.
-- A stream advances its offset when the transaction that reads it commits, so
-- without the shared transaction the first MERGE consumes the stream and the
-- second finds it empty.
BEGIN;

-- Merge changes from stream into target (inserts + updates)
MERGE INTO SILVER_DB.CUSTOMERS.customer AS target
USING (
    SELECT *
    FROM RAW_DB.CDC.customer_changes
    WHERE METADATA$ACTION = 'INSERT'  -- Includes both inserts and "new" half of updates
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY _loaded_at DESC
    ) = 1  -- Deduplicate: keep only the latest change per customer
) AS source
ON target.customer_id = source.customer_id
WHEN MATCHED AND source.METADATA$ISUPDATE = TRUE THEN
    UPDATE SET
        target.name = source.name,
        target.email = source.email,
        target.status = source.status,
        target.updated_at = source.updated_at,
        target._cdc_action = 'UPDATE',
        target._cdc_timestamp = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, email, status, created_at, updated_at,
            _cdc_action, _cdc_timestamp)
    VALUES (source.customer_id, source.name, source.email, source.status,
            source.created_at, source.updated_at, 'INSERT', CURRENT_TIMESTAMP());

-- Apply deletes (soft delete pattern — mark as inactive rather than removing)
MERGE INTO SILVER_DB.CUSTOMERS.customer AS target
USING (
    SELECT *
    FROM RAW_DB.CDC.customer_changes
    WHERE METADATA$ACTION = 'DELETE'
    AND METADATA$ISUPDATE = FALSE  -- True deletes, not the "old" half of updates
) AS source
ON target.customer_id = source.customer_id
WHEN MATCHED THEN
    UPDATE SET
        target.status = 'DELETED',
        target._cdc_action = 'DELETE',
        target._cdc_timestamp = CURRENT_TIMESTAMP();

COMMIT;

-- Verify the MERGE consumed the stream. Streams advance their offset only when
-- a downstream MERGE includes them in the FROM clause and commits successfully,
-- so a zero count here confirms the consumption pattern is working.
SELECT COUNT(*) FROM RAW_DB.CDC.customer_changes;

-- Schedule the MERGE pair as a Snowflake Task. The task body wraps both
-- MERGE statements in the same explicit transaction, for the same reason as
-- above. A 5-minute interval keeps the silver customer table fresh for
-- downstream queries without manual triggers.
CREATE OR REPLACE TASK SILVER_DB.CUSTOMERS.apply_customer_cdc
    WAREHOUSE = BOOK_WH
    SCHEDULE = '5 minute'
AS
BEGIN
    BEGIN TRANSACTION;

    -- Inserts + updates
    MERGE INTO SILVER_DB.CUSTOMERS.customer AS target
    USING (
        SELECT *
        FROM RAW_DB.CDC.customer_changes
        WHERE METADATA$ACTION = 'INSERT'
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY _loaded_at DESC
        ) = 1
    ) AS source
    ON target.customer_id = source.customer_id
    WHEN MATCHED AND source.METADATA$ISUPDATE = TRUE THEN
        UPDATE SET
            target.name = source.name,
            target.email = source.email,
            target.status = source.status,
            target.updated_at = source.updated_at,
            target._cdc_action = 'UPDATE',
            target._cdc_timestamp = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN
        INSERT (customer_id, name, email, status, created_at, updated_at,
                _cdc_action, _cdc_timestamp)
        VALUES (source.customer_id, source.name, source.email, source.status,
                source.created_at, source.updated_at, 'INSERT',
                CURRENT_TIMESTAMP());

    -- Soft deletes (true deletes only, not the "old" half of updates)
    MERGE INTO SILVER_DB.CUSTOMERS.customer AS target
    USING (
        SELECT *
        FROM RAW_DB.CDC.customer_changes
        WHERE METADATA$ACTION = 'DELETE'
          AND METADATA$ISUPDATE = FALSE
    ) AS source
    ON target.customer_id = source.customer_id
    WHEN MATCHED THEN
        UPDATE SET
            target.status = 'DELETED',
            target._cdc_action = 'DELETE',
            target._cdc_timestamp = CURRENT_TIMESTAMP();

    COMMIT;
END;

ALTER TASK SILVER_DB.CUSTOMERS.apply_customer_cdc RESUME;



-- =============================================================================
-- Section 5.3: Dynamic Tables — CDC Without the Plumbing
-- =============================================================================

-- Create a Dynamic Table that automatically tracks customer changes.
-- Snowflake creates and manages the underlying stream automatically — no manual
-- MERGE or offset management. The QUALIFY clause performs the same dedup as the
-- explicit MERGE pattern. Sized for the per-refresh transformation cost.
CREATE OR REPLACE DYNAMIC TABLE SILVER_DB.CUSTOMERS.customer_dynamic
    TARGET_LAG = '5 minutes'
    WAREHOUSE = BOOK_WH
AS
SELECT
    customer_id,
    name,
    email,
    status,
    created_at,
    updated_at
FROM RAW_DB.LANDING.customers
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY updated_at DESC
) = 1;

-- Verify the refresh status. data_timestamp should track close to target_lag
-- (within a few minutes); a stalled value usually indicates warehouse
-- cluster scaling issues or refresh logic failures.
-- There is no INFORMATION_SCHEMA.DYNAMIC_TABLES view; use SHOW and read the
-- output through RESULT_SCAN. data_timestamp shows the freshness of the data
-- and should advance every ~5 minutes; scheduling_state should be ACTIVE.
SHOW DYNAMIC TABLES LIKE 'customer_dynamic';

SELECT "name", "target_lag", "scheduling_state", "data_timestamp"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));



-- =============================================================================
-- Section 5.4: Schema Evolution in CDC Pipelines
-- =============================================================================

USE DATABASE RAW_DB;
USE SCHEMA LANDING;

-- ---------------------------------------------------------------------------
-- Pattern 1: Evolving a VARIANT-based pipeline (zero-maintenance schema change)
-- ---------------------------------------------------------------------------

-- Resilient landing table with a single VARIANT payload column. The payload
-- absorbs every source field, including new ones, so the landing table never
-- needs a schema migration when the source changes.
CREATE OR REPLACE TABLE RAW_DB.LANDING.customers_raw (
    source_id STRING,
    payload VARIANT,
    _cdc_operation STRING,  -- INSERT, UPDATE, DELETE
    _source_timestamp TIMESTAMP_NTZ,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Typed view: the contract downstream MERGEs and transformations consume.
-- When the source adds a column, update the view (e.g.,
-- `payload:preferences::VARIANT AS preferences`) — no table migration, no
-- pipeline restart, no data loss.
CREATE OR REPLACE VIEW RAW_DB.LANDING.customers_typed AS
SELECT
    payload:customer_id::STRING AS customer_id,
    payload:name::STRING AS name,
    payload:email::STRING AS email,
    payload:status::STRING AS status,
    payload:phone::STRING AS phone,
    payload:created_at::TIMESTAMP_NTZ AS created_at,
    payload:updated_at::TIMESTAMP_NTZ AS updated_at,
    _cdc_operation,
    _source_timestamp,
    _loaded_at
FROM RAW_DB.LANDING.customers_raw;

-- Verify the typed extraction is working before pointing downstream consumers
-- at it.
SELECT customer_id, name, email, status, phone
FROM RAW_DB.LANDING.customers_typed
LIMIT 10;


-- ---------------------------------------------------------------------------
-- Pattern 2: Evolving a schematized pipeline (controlled ALTER on typed table)
-- ---------------------------------------------------------------------------

-- Core diff query: identifies columns present in the source but missing in the
-- target. The stored procedure below wraps this query and applies the
-- `ALTER TABLE ADD COLUMN` for each missing column.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = UPPER('customers_source')
EXCEPT
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = UPPER('customers_landing');

-- Self-healing schematized pipeline procedure. Detects new columns in the
-- source and applies them to the target automatically.
CREATE OR REPLACE PROCEDURE RAW_DB.LANDING.usp_sync_target_schema(
    source_table STRING,
    target_table STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    new_columns RESULTSET;
    alter_stmt STRING;
BEGIN
    new_columns := (
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_name = UPPER(:source_table)
        EXCEPT
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_name = UPPER(:target_table)
    );

    FOR col IN new_columns DO
        alter_stmt := 'ALTER TABLE ' || :target_table ||
                      ' ADD COLUMN ' || col.column_name ||
                      ' ' || col.data_type;
        EXECUTE IMMEDIATE :alter_stmt;
    END FOR;

    RETURN 'Schema evolution complete';
END;
$$;

-- Schedule the schema-detection procedure as a Snowflake Task so the diff runs
-- on a regular cadence without manual intervention. Daily or weekly is typical
-- depending on how often the source schema changes.
CREATE OR REPLACE TASK RAW_DB.LANDING.detect_schema_drift
    WAREHOUSE = BOOK_WH
    SCHEDULE = 'USING CRON 0 2 * * * UTC'  -- 2am UTC daily
AS
CALL RAW_DB.LANDING.usp_sync_target_schema(
    'customers_source', 'customers_landing');

ALTER TASK RAW_DB.LANDING.detect_schema_drift RESUME;

-- After the procedure runs, verify new source columns are showing up.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'LANDING' AND table_name = 'CUSTOMERS_LANDING'
ORDER BY ordinal_position;


-- ---------------------------------------------------------------------------
-- Schema drift monitoring (applies to either pattern)
-- ---------------------------------------------------------------------------
-- Snapshot the documented schema the first time each table is deployed, then
-- compare against the live information schema on a daily cadence. Differences
-- against the baseline indicate the source has changed.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'LANDING' AND table_name = 'CUSTOMERS_RAW'
ORDER BY ordinal_position;


