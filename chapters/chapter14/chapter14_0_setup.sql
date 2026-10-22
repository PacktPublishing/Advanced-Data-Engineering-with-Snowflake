-- =============================================================================
-- Chapter 14: Data Modeling in Snowflake using AI-Assisted Practices - Setup
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: the staging fixtures every section of the chapter reads. Run this
-- ONCE, before any other chapter14_N_*.sql file. The section files are
-- independent of each other once this has completed: a reader following only
-- section 3 runs chapter14_2_scd_patterns.sql and nothing else.
--
-- Prerequisites:
--   - setup/snowflake_setup.sql (creates the UTIL database and BOOK_WH).
--   - Chapter 5 completed: gold_db.transactions.fact_transactions and the
--     SCD Type 2 gold_db.customers.dim_customers exist with the Chapter 5
--     fixture (chapter5_1_window_functions.sql, chapter5_3_incremental_patterns.sql).
--   - Chapter 12 completed: chapter12_0_setup.sql has added
--     gold_db.merchants.dim_merchants, gold_db.transactions.fact_refunds,
--     gold_db.customers.dim_customers_current, and the 50,000-row top-up.
--     The guard block below stops with one named error per missing object.
--     Chapter 12 tells its readers to run chapter12_teardown.sql after
--     Chapter 13; that teardown removes these objects, so run
--     chapter12_0_setup.sql again before this file if you did.
--
-- Role convention: SYSADMIN owns databases, schemas, tables, and views
-- throughout the book. Any role with USAGE and CREATE SCHEMA on gold_db and
-- raw_db, CREATE TABLE / CREATE VIEW on the target schemas, SELECT, INSERT,
-- UPDATE, and DELETE on the shared gold tables, and USAGE on BOOK_WH works.
--
-- Placeholder convention: <REPLACE: ...> marks values you must substitute.
-- This file has none. Objects the book standardizes (gold_db, raw_db, BOOK_WH)
-- are used literally.
--
-- Verification status (offline only, no live Snowflake run yet): every
-- plain SQL statement in the six files parses in sqlglot's Snowflake dialect,
-- and chapter14_logic_sim.py replays the relational statements (DDL, DML,
-- views, validation queries) against a DuckDB emulation of the Chapter 5 + 12
-- gold layer scaled to 5,024 payments, checking the quoted counts, reruns,
-- the invariant counterexamples, and a full-column restore of both shared
-- dimensions after teardown. Snowflake-only behavior is NOT covered offline:
-- the Snowflake Scripting blocks and their exception paths, RELY and the
-- TABLE_CONSTRAINTS metadata, EXPLAIN, and COMMENT ON and UNSET COMMENT. No
-- preview features are used, so any current edition applies.
--
-- THIS CHAPTER LATER WRITES INTO TWO TABLES EARLIER CHAPTERS OWN:
--   gold_db.merchants.dim_merchants   (Type 1 and Type 3 changes, section 3)
--   gold_db.customers.dim_customers   (two closed versions + three new rows)
-- This script snapshots dim_merchants once (dim_merchants_before_ch14) and
-- fixes the changed rows to known ids (every row it adds carries a MERCH-CH14-
-- or CUST-CH14- id), so chapter14_teardown.sql reverses every change. Re-running this file before any section file is safe:
-- fixtures are rebuilt from the pristine snapshot, never from the
-- possibly-modified live table. After section 3 has run, the guard below
-- stops with a message asking for chapter14_teardown.sql first, since every
-- count the chapter quotes assumes a fresh dimension.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;

-- Safety net. Chapters 4, 5, and 12 normally create these; IF NOT EXISTS keeps
-- this file runnable on an account where only some of them are present.
CREATE DATABASE IF NOT EXISTS gold_db;
CREATE SCHEMA IF NOT EXISTS gold_db.transactions;
CREATE SCHEMA IF NOT EXISTS gold_db.customers;
CREATE SCHEMA IF NOT EXISTS gold_db.merchants;
CREATE DATABASE IF NOT EXISTS raw_db;
CREATE SCHEMA IF NOT EXISTS raw_db.crm;

-- New in Chapter 14: the partner operations feed that corrects and
-- reclassifies merchants. Chapter-owned; teardown drops it.
CREATE SCHEMA IF NOT EXISTS raw_db.partners
    COMMENT = 'Chapter 14 partner-operations staging (merchant feeds)';

USE DATABASE gold_db;


-- =============================================================================
-- 1. Prerequisite guard
-- -----------------------------------------------------------------------------
-- The labs only produce the counts the chapter quotes on top of the Chapter 12
-- gold layer. Stop here with a readable message instead of failing later
-- inside a MERGE.
-- =============================================================================

-- One exception per check, each naming the object that is missing and the
-- script that supplies it, so a failed run points at one thing to fix.
EXECUTE IMMEDIATE $$
DECLARE
    no_payments EXCEPTION (-20014,
        'gold_db.transactions.fact_transactions is empty. Run the Chapter 5 scripts (chapter5_1_window_functions.sql first) and then chapter12_0_setup.sql, which adds the 50,000-row top-up this chapter counts on.');
    no_refunds EXCEPTION (-20015,
        'gold_db.transactions.fact_refunds is empty. Run chapter12_0_setup.sql, which creates and seeds it.');
    no_merchants EXCEPTION (-20016,
        'gold_db.merchants.dim_merchants is empty. Run chapter12_0_setup.sql, which builds it from the fact table. If you ran chapter12_teardown.sql after Chapter 13, run chapter12_0_setup.sql again before this file.');
    no_seed_customers EXCEPTION (-20017,
        'Fewer than 50 current CH12-SEED rows in gold_db.customers.dim_customers. Run chapter12_0_setup.sql, which seeds the 500 Chapter 12 customers.');
    movers_not_current EXCEPTION (-20018,
        'CUST-CH12-0007 and CUST-CH12-0042 are not both current CH12-SEED rows in dim_customers. Either chapter12_0_setup.sql has not run, or a previous run of chapter14_2_scd_patterns.sql closed them: run chapter14_teardown.sql, then this file again.');
    no_current_view EXCEPTION (-20019,
        'The view gold_db.customers.dim_customers_current is missing. Run chapter12_0_setup.sql, which creates it.');
    payments NUMBER;
    refunds NUMBER;
    merchants NUMBER;
    customers NUMBER;
    movers NUMBER;
    current_view NUMBER;
BEGIN
    -- A missing table raises a statement error on its own at its SELECT; the
    -- handler at the bottom re-raises it so the error names the object.
    SELECT COUNT(*) INTO :payments FROM gold_db.transactions.fact_transactions;
    IF (payments = 0) THEN RAISE no_payments; END IF;

    SELECT COUNT(*) INTO :refunds FROM gold_db.transactions.fact_refunds;
    IF (refunds = 0) THEN RAISE no_refunds; END IF;

    SELECT COUNT(*) INTO :merchants FROM gold_db.merchants.dim_merchants;
    IF (merchants = 0) THEN RAISE no_merchants; END IF;

    SELECT COUNT(*) INTO :customers
      FROM gold_db.customers.dim_customers
     WHERE record_hash = 'CH12-SEED' AND is_current = TRUE;
    IF (customers < 50) THEN RAISE no_seed_customers; END IF;

    SELECT COUNT(*) INTO :movers
      FROM gold_db.customers.dim_customers
     WHERE customer_id IN ('CUST-CH12-0007', 'CUST-CH12-0042')
       AND record_hash = 'CH12-SEED' AND is_current = TRUE;
    IF (movers <> 2) THEN RAISE movers_not_current; END IF;

    SELECT COUNT(*) INTO :current_view
      FROM gold_db.information_schema.views
     WHERE table_schema = 'CUSTOMERS' AND table_name = 'DIM_CUSTOMERS_CURRENT';
    IF (current_view = 0) THEN RAISE no_current_view; END IF;

    RETURN 'Prerequisites present: ' || payments || ' payments, ' || refunds
           || ' refunds, ' || merchants || ' merchants, ' || customers
           || ' seeded current customers, both movers current, current view present.';
EXCEPTION
    WHEN STATEMENT_ERROR THEN
        -- A missing table lands here, but so does a privilege error. Re-raise
        -- the original error: 'does not exist or not authorized' names the
        -- object, and the file still stops on a stop-on-error client.
        RAISE;
END;
$$;

-- Expected: 'Prerequisites present: 50024 payments, about 2250 refunds, 47
-- merchants, 500 seeded current customers, both movers current, current view
-- present.' with the stock Chapter 5 + Chapter 12 fixtures (the refund count
-- is hash-derived in the Chapter 12 seed, roughly 1.5 events per REFUNDED
-- payment). An 'Object ... does not exist or not authorized' error names the
-- table that is missing or unreadable by this role. Errors -20014 to -20019
-- each name one missing prerequisite and the script that supplies it; -20018
-- also fires after a Chapter 14 section 3 run that was not torn down, since
-- the movers are current only before that section runs. The electronics
-- merchants the Type 3 example needs are no longer a prerequisite: block 5
-- supplies them when the dimension has none.


-- =============================================================================
-- 2. Pristine snapshot of the merchant dimension
-- -----------------------------------------------------------------------------
-- Section 3 overwrites merchant rows (Type 1) and adds two columns (Type 3).
-- The snapshot is created only once (IF NOT EXISTS), so a re-run after
-- section 3 keeps the original values, and both fixtures below derive from it
-- so they are identical on every run. Teardown restores from it, then drops it.
-- =============================================================================

CREATE TABLE IF NOT EXISTS raw_db.partners.dim_merchants_before_ch14
    COMMENT = 'Chapter 14 reversibility snapshot of gold_db.merchants.dim_merchants'
AS
SELECT merchant_id, merchant_name, merchant_category, merchant_city
  FROM gold_db.merchants.dim_merchants;

-- Expected: 'Table DIM_MERCHANTS_BEFORE_CH14 successfully created.' on the
-- first run, 'already exists, statement succeeded.' on every later run.


-- =============================================================================
-- 3. Fixture for Type 1: the partner operations correction feed
-- -----------------------------------------------------------------------------
-- Four rows: three corrections to existing Chapter 12 merchants and one new
-- merchant. The first two corrections change the city to values the Chapter 12
-- city list never uses, the third changes the category, so every correction
-- differs from the dimension in at least one column and the chapter's MERGE
-- reports 'number of rows inserted: 1' and 'number of rows updated: 3'.
-- The 'electronics' merchants are excluded on purpose: they belong to the
-- Type 3 reclassification fixture in block 5.
-- =============================================================================

CREATE OR REPLACE TABLE raw_db.partners.stg_merchant_updates
    COMMENT = 'Chapter 14 Type 1 fixture: 3 corrections + 1 new merchant'
AS
WITH picks AS (
    SELECT merchant_id, merchant_name, merchant_category, merchant_city,
           ROW_NUMBER() OVER (ORDER BY merchant_id) AS rn
      FROM raw_db.partners.dim_merchants_before_ch14
     WHERE merchant_id LIKE 'MERCH-CH12-%'
       AND UPPER(merchant_category) <> 'ELECTRONICS'
)
SELECT merchant_id,
       merchant_name,
       CASE WHEN rn = 3
            THEN IFF(merchant_category = 'retail', 'dining', 'retail')
            ELSE merchant_category END                 AS merchant_category,
       CASE WHEN rn = 1 THEN 'Miami'
            WHEN rn = 2 THEN 'Orlando'
            ELSE merchant_city END                     AS merchant_city,
       '2026-07-02 05:00:00'::TIMESTAMP_NTZ            AS updated_at
  FROM picks
 WHERE rn <= 3
UNION ALL
SELECT 'MERCH-CH14-NEW01', 'Harbour Kitchen Supply', 'groceries', 'Tampa',
       '2026-07-02 05:00:00'::TIMESTAMP_NTZ;

-- Expected: 4 rows. MERCH-CH12-00 and MERCH-CH12-01 move to Miami and Orlando,
-- MERCH-CH12-02 changes category, MERCH-CH14-NEW01 is new.


-- =============================================================================
-- 4. Fixture for Type 2: the CRM delta extract
-- -----------------------------------------------------------------------------
-- Three rows: two seeded customers who moved to Florida (a state the Chapter 12
-- seed never assigns, so the change is guaranteed) and one new signup. Names and
-- emails come from the seed rows so only the address attributes differ. The
-- extract timestamp is fixed inside the seeded window so the point-in-time join
-- in section 3.4 has payments on both sides of the move. For this fixture,
-- extract_ts is assumed to equal the business-effective time of the change.
-- If extract_ts instead records extraction time, the windows describe when
-- changes were observed. Late or retroactive changes need a separate
-- effective timestamp and correction policy.
--
-- Why a delta extract and not a full snapshot: the Chapter 12 seed stores the
-- literal tag 'CH12-SEED' in record_hash rather than a real hash, so a full
-- snapshot would make every seeded customer look changed. A delta extract is
-- sufficient to demonstrate changed and new customers in this lab.
-- =============================================================================

CREATE OR REPLACE TABLE raw_db.crm.stg_customer_extract
    COMMENT = 'Chapter 14 Type 2 fixture: CRM delta extract, 2 movers + 1 new signup'
AS
SELECT d.customer_id,
       d.customer_name,
       d.email,
       '1200 Biscayne Blvd'                            AS address_line1,
       'Miami'                                         AS city,
       'FL'                                            AS state,
       '33132'                                         AS postal_code,
       '2026-03-01 06:00:00'::TIMESTAMP_NTZ            AS extract_ts
  FROM gold_db.customers.dim_customers d
 WHERE d.customer_id = 'CUST-CH12-0007'
   AND d.record_hash = 'CH12-SEED'
UNION ALL
SELECT d.customer_id,
       d.customer_name,
       d.email,
       '400 W Church St',
       'Orlando',
       'FL',
       '32801',
       '2026-03-01 06:00:00'::TIMESTAMP_NTZ
  FROM gold_db.customers.dim_customers d
 WHERE d.customer_id = 'CUST-CH12-0042'
   AND d.record_hash = 'CH12-SEED'
UNION ALL
SELECT 'CUST-CH14-0001',
       'Priya Raman',
       'priya.raman@example.com',
       '77 Bayshore Blvd',
       'Tampa',
       'FL',
       '33606',
       '2026-03-01 06:00:00'::TIMESTAMP_NTZ;

-- Expected: 3 rows.


-- =============================================================================
-- 5. Fixture for Type 3: the category reclassification
-- -----------------------------------------------------------------------------
-- The partner team folds the legacy electronics category into retail. With the
-- stock fixture the two Chapter 5 merchants MERCH_ELEC_1 and MERCH_ELEC_2
-- carry that category: Chapter 5 writes ELECTRONICS into the fact and
-- chapter12_0_setup.sql lower-cases it when it builds dim_merchants, so every
-- category test here ignores case. A dimension that holds no electronics
-- merchant at all (a replaced Chapter 5 fixture, or a dimension rebuilt from
-- a truncated fact) gets two chapter-owned electronics merchants instead, so
-- the chapter's MERGE reports 'number of rows updated: 2' either way. The
-- teardown's MERCH-CH14- delete removes them.
-- =============================================================================

INSERT INTO gold_db.merchants.dim_merchants
    (merchant_id, merchant_name, merchant_category, merchant_city)
SELECT v.merchant_id, v.merchant_name, v.merchant_category, v.merchant_city
  FROM (VALUES
        ('MERCH-CH14-ELEC01', 'Bayfront Electronics', 'electronics', 'Tampa'),
        ('MERCH-CH14-ELEC02', 'Gulf Coast Audio',     'electronics', 'Clearwater'))
       AS v (merchant_id, merchant_name, merchant_category, merchant_city)
 WHERE NOT EXISTS (SELECT 1
                     FROM raw_db.partners.dim_merchants_before_ch14
                    WHERE UPPER(merchant_category) = 'ELECTRONICS')
   AND NOT EXISTS (SELECT 1
                     FROM gold_db.merchants.dim_merchants m
                    WHERE m.merchant_id = v.merchant_id);

-- Expected: number of rows inserted: 0 with the stock fixture, 2 on an
-- account whose merchant dimension has no electronics merchant.

CREATE OR REPLACE TABLE raw_db.partners.stg_merchant_reclass
    COMMENT = 'Chapter 14 Type 3 fixture: electronics merchants folded into retail'
AS
SELECT merchant_id,
       'retail'                                        AS new_category,
       '2026-06-30 23:59:00'::TIMESTAMP_NTZ            AS reclass_ts
  FROM raw_db.partners.dim_merchants_before_ch14
 WHERE UPPER(merchant_category) = 'ELECTRONICS'
UNION ALL
SELECT merchant_id,
       'retail',
       '2026-06-30 23:59:00'::TIMESTAMP_NTZ
  FROM gold_db.merchants.dim_merchants
 WHERE merchant_id IN ('MERCH-CH14-ELEC01', 'MERCH-CH14-ELEC02');

-- Expected: 2 rows, the Chapter 5 pair with the stock fixture or the
-- chapter-owned pair without it.


-- =============================================================================
-- 6. Fixture check
-- =============================================================================

SELECT 'stg_merchant_updates'  AS fixture, COUNT(*) AS rows_loaded
  FROM raw_db.partners.stg_merchant_updates
UNION ALL
SELECT 'stg_customer_extract', COUNT(*)
  FROM raw_db.crm.stg_customer_extract
UNION ALL
SELECT 'stg_merchant_reclass', COUNT(*)
  FROM raw_db.partners.stg_merchant_reclass
UNION ALL
SELECT 'electronics merchants in dim_merchants', COUNT(*)
  FROM gold_db.merchants.dim_merchants
 WHERE UPPER(merchant_category) = 'ELECTRONICS';

-- Expected: 4, 3, 2, 2. Run chapter14_1_star_schema.sql next.
