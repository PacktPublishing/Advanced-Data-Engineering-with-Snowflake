-- =========================================================================
-- Chapter 7: Snowpark Python for Data Engineering: Section 0 setup
-- =========================================================================
-- Prereqs:
--   * Chapter 5 ran (gold_db.transactions.fact_transactions exists)
--   * BOOK_WH warehouse exists from setup/snowflake_setup.sql
--   * Role with CREATE STAGE / CREATE TABLE on gold_db
--
-- Role discipline: everything this file creates (databases, schemas, a
-- warehouse, stages, tables, seed rows) is SYSADMIN scope. ACCOUNTADMIN is
-- not required anywhere in this script; the one ACCOUNTADMIN statement in
-- the chapter (ALTER ACCOUNT SET EVENT_TABLE, Section 4.4) is shown in the
-- chapter text and is not part of this setup.
-- =========================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;

-- Safety net: ensure the databases this chapter touches exist. Chapters 1-5
-- create them (and fill fact_transactions with data); IF NOT EXISTS only
-- prevents a hard "does not exist" error on fresh accounts -- the Section 1+
-- labs still need the Chapter 5 data to produce meaningful output.
CREATE DATABASE IF NOT EXISTS gold_db;
CREATE SCHEMA IF NOT EXISTS gold_db.transactions;
CREATE SCHEMA IF NOT EXISTS gold_db.customers;

-- -------------------------------------------------------------------------
-- 0.1  Snowpark-optimized warehouse used by the Section 3 UDF benchmark
-- -------------------------------------------------------------------------
-- As of August 2026, Snowpark-optimized warehouses are available in every
-- edition; the default memory configuration (MEMORY_16X) requires a minimum
-- size of MEDIUM (X-Small/Small return error 000676 with "X-Small warehouse
-- size is not supported for SNOWPARK-OPTIMIZED warehouse type."). The
-- warehouse is still named *_XS_SO for continuity with the chapter text --
-- only the underlying compute size differs. MEDIUM at the Snowpark-optimized
-- credit rate is not cheap: it ships INITIALLY_SUSPENDED with a 60-second
-- auto-suspend, so it only bills while the Section 3 benchmark runs.

CREATE WAREHOUSE IF NOT EXISTS BOOK_WH_XS_SO
    WAREHOUSE_SIZE = 'MEDIUM'
    WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Snowpark-optimized warehouse for chapter7 UDF benchmark (MEDIUM is the minimum SO size).';

-- -------------------------------------------------------------------------
-- 0.2  Schemas and stages for chapter7 artifacts
-- -------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS gold_db.public;
CREATE SCHEMA IF NOT EXISTS gold_db.control;
CREATE SCHEMA IF NOT EXISTS gold_db.staging;

CREATE STAGE IF NOT EXISTS gold_db.public.udf_stage
    COMMENT = 'Internal stage for Snowpark UDF and UDTF artifacts (chapter 7).';

CREATE STAGE IF NOT EXISTS gold_db.public.sproc_stage
    COMMENT = 'Internal stage for Snowpark stored procedure artifacts (chapter 7).';

-- -------------------------------------------------------------------------
-- 0.3  Control table referenced by promote_customer_batch (Section 4.2)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold_db.control.batch_log (
    batch_id   STRING,
    status     STRING,
    logged_at  TIMESTAMP_NTZ
);

-- -------------------------------------------------------------------------
-- 0.4  Target dimension used by promote_customer_batch (Section 4.2)
-- -------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS gold_db.customers;

CREATE TABLE IF NOT EXISTS gold_db.customers.dim_customers (
    customer_id     STRING,
    customer_name   STRING,
    email           STRING,
    address_line1   STRING,
    city            STRING,
    state           STRING,
    postal_code     STRING,
    effective_from  TIMESTAMP_NTZ,
    effective_to    TIMESTAMP_NTZ,
    is_current      BOOLEAN
);

-- -------------------------------------------------------------------------
-- 0.5  Staging table the stored procedure reads from
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold_db.staging.customer_batch (
    batch_id        STRING,
    customer_id     STRING,
    customer_name   STRING,
    email           STRING,
    address_line1   STRING,
    city            STRING,
    state           STRING,
    postal_code     STRING,
    received_at     TIMESTAMP_NTZ
);

-- -------------------------------------------------------------------------
-- 0.6  Seed one valid + one invalid batch so the procedure has data to test
-- -------------------------------------------------------------------------
-- The procedure returns 'PROMOTED' for batch 0001, 'INVALID' for batch 0002,
-- and 'EMPTY' for any batch_id not present.

DELETE FROM gold_db.staging.customer_batch
WHERE batch_id IN ('2026-04-29-batch-0001', '2026-04-29-batch-0002');

INSERT INTO gold_db.staging.customer_batch VALUES
    ('2026-04-29-batch-0001', 'C2001', 'Avery Chen',  'avery@example.com',
     '12 Pine St', 'Austin',   'TX', '78701', CURRENT_TIMESTAMP()),
    ('2026-04-29-batch-0001', 'C2002', 'Priya Shah',  'priya@example.com',
     '45 Oak Ave', 'San Diego','CA', '92101', CURRENT_TIMESTAMP()),
    ('2026-04-29-batch-0002', NULL,    'Bad Row One', 'bad1@example.com',
     '99 Bug Ln', 'Nowhere',  'XX', '00000', CURRENT_TIMESTAMP());

-- -------------------------------------------------------------------------
-- 0.7  Sanity selects
-- -------------------------------------------------------------------------
SELECT COUNT(*) AS staging_rows FROM gold_db.staging.customer_batch;
SHOW STAGES IN SCHEMA gold_db.public;
