-- =========================================================================
-- Chapter 8: Migrating Spark Workloads to Snowpark: Section 0 setup
-- =========================================================================
-- Prereqs:
--   * gold_db.transactions.fact_transactions exists (Chapters 4-5)
--   * gold_db.customers.dim_customers exists (Chapter 7)
--   * BOOK_WH warehouse exists from setup/snowflake_setup.sql
--   * @lake_stage external stage exists from Chapter 3
--   * A role (TECHFLOW_ETL here) that submitted jobs run under
-- =========================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;

-- Safety net: ensure the databases this chapter touches exist. Chapters 4-7
-- create them (and fill fact_transactions / dim_customers with data);
-- IF NOT EXISTS only prevents a hard "does not exist" error -- the migration
-- labs still need the earlier chapters' data to produce meaningful output.
CREATE DATABASE IF NOT EXISTS gold_db;
CREATE SCHEMA IF NOT EXISTS gold_db.transactions;
CREATE SCHEMA IF NOT EXISTS gold_db.customers;

-- -------------------------------------------------------------------------
-- 0.1  Compute pool that hosts the Snowpark Submit driver (Section 3.1)
-- -------------------------------------------------------------------------
-- AUTO_SUSPEND_SECS + AUTO_RESUME matter more than the instance family: a
-- nightly job pays for roughly its own duration instead of 24 hours of
-- standing nodes, at the cost of a 30-60 second cold start on resume.

CREATE COMPUTE POOL IF NOT EXISTS TECHFLOW_SPARK_POOL
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_SUSPEND_SECS = 300
  AUTO_RESUME = TRUE;

-- -------------------------------------------------------------------------
-- 0.2  Privilege set for the submitting role (Section 3.1, step 3)
-- -------------------------------------------------------------------------
-- Snowpark Submit creates a job service in a schema and reads files from a
-- stage, so the role needs more than warehouse access. Grant all five before
-- the first submit (see the PRO TIP in Section 3.1): a missing grant fails
-- minutes into the run, not fast.

GRANT USAGE ON DATABASE gold_db TO ROLE TECHFLOW_ETL;
GRANT USAGE ON SCHEMA gold_db.transactions TO ROLE TECHFLOW_ETL;
GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE TECHFLOW_ETL;
GRANT USAGE ON COMPUTE POOL TECHFLOW_SPARK_POOL TO ROLE TECHFLOW_ETL;
GRANT CREATE SERVICE ON SCHEMA gold_db.transactions TO ROLE TECHFLOW_ETL;
GRANT READ ON STAGE gold_db.transactions.lake_stage TO ROLE TECHFLOW_ETL;

-- -------------------------------------------------------------------------
-- 0.3  External table over the upstream Avro feed (Section 4.2)
-- -------------------------------------------------------------------------
-- Avro and ORC are not in the Snowpark Connect read path. Define the external
-- table once and let migrated Spark code read it like any other table. The
-- FILE_FORMAT clause is where the format knowledge lives now, instead of in
-- each Spark script.
--
-- PREREQUISITE: @lake_stage is the external stage built in Chapter 3,
-- Building Batch Data Ingestion Patterns. It is NOT created here. If your
-- account only has the Chapter 7 UDF_STAGE / SPROC_STAGE, create the Chapter 3
-- storage integration and stage first, or this statement and the READ grant in
-- section 0.2 will fail with "stage does not exist".

CREATE OR REPLACE EXTERNAL TABLE gold_db.transactions.ext_payment_events
  LOCATION = @lake_stage/payment_events/
  FILE_FORMAT = (TYPE = AVRO)
  AUTO_REFRESH = TRUE;

-- -------------------------------------------------------------------------
-- 0.4  Target table the migrated settlement job writes (Section 3.1)
-- -------------------------------------------------------------------------
-- daily_settlement.py writes with mode("overwrite").saveAsTable(...), so the
-- table is created on first run; this DDL just documents the shape and lets
-- the verify query run before the first submit.

CREATE TABLE IF NOT EXISTS gold_db.transactions.daily_settlement (
    merchant_id         STRING,
    settle_date         DATE,
    settled_amount_usd  NUMBER(18,2),
    settled_txn_count   NUMBER
);

-- -------------------------------------------------------------------------
-- 0.5  Sanity checks
-- -------------------------------------------------------------------------
SHOW COMPUTE POOLS LIKE 'TECHFLOW_SPARK_POOL';
SELECT COUNT(*) AS ext_payment_event_rows FROM gold_db.transactions.ext_payment_events;
