-- =============================================================================
-- Chapter 12: Semantic Layer and Semantic Views - Section 2.2 setup
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 2.2 Preparing the TechFlow Gold Layer. Run this ONCE, before any
-- other chapter12_N_*.sql file. Every section file below it runs standalone
-- top to bottom once this has completed.
--
-- Prerequisites:
--   - setup/snowflake_setup.sql (creates the UTIL database and BOOK_WH).
--   - Chapter 5 completed: gold_db.transactions.fact_transactions and
--     gold_db.customers.dim_customers exist and carry the Chapter 5 fixture.
--     The guards below create the database and schemas if they are missing,
--     but the labs only produce meaningful output on top of Chapter 5 data.
--
-- Role convention: SYSADMIN owns databases, schemas, tables, and views
-- throughout the book. Any role with USAGE and CREATE SCHEMA on gold_db,
-- CREATE TABLE / CREATE VIEW on the target schemas, SELECT and INSERT and
-- DELETE on the two shared Chapter 5 tables, and USAGE on BOOK_WH also works.
--
-- If Chapter 5 ran as ACCOUNTADMIN, that role still owns gold_db, its
-- transactions and customers schemas, and the two tables, and ownership of a
-- database does not carry down to objects another role created. Run these
-- once as ACCOUNTADMIN before this script, or grant SYSADMIN the privileges
-- above on each of the five objects instead:
--
--   GRANT OWNERSHIP ON DATABASE gold_db
--     TO ROLE SYSADMIN COPY CURRENT GRANTS;
--   GRANT OWNERSHIP ON SCHEMA gold_db.transactions
--     TO ROLE SYSADMIN COPY CURRENT GRANTS;
--   GRANT OWNERSHIP ON SCHEMA gold_db.customers
--     TO ROLE SYSADMIN COPY CURRENT GRANTS;
--   GRANT OWNERSHIP ON TABLE gold_db.transactions.fact_transactions
--     TO ROLE SYSADMIN COPY CURRENT GRANTS;
--   GRANT OWNERSHIP ON TABLE gold_db.customers.dim_customers
--     TO ROLE SYSADMIN COPY CURRENT GRANTS;
--
-- Placeholder convention: <REPLACE: ...> marks values you must substitute.
-- This file has none - every object the book standardizes is used literally.
--
-- THIS SCRIPT WRITES INTO TWO TABLES EARLIER CHAPTERS OWN:
--   gold_db.transactions.fact_transactions  (50,000 rows, 'TXN-CH12-' prefix)
--   gold_db.customers.dim_customers         (rows tagged record_hash CH12-*)
-- Both markers exist so chapter12_teardown.sql reverses this exactly. Nothing
-- else in gold_db is modified. Re-running is safe: each seeding block deletes
-- its own tagged rows before inserting.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;

-- Safety net. Chapter 5 normally creates these; IF NOT EXISTS keeps this file
-- runnable on an account where only some of them are present.
CREATE DATABASE IF NOT EXISTS gold_db;
CREATE SCHEMA IF NOT EXISTS gold_db.transactions;
CREATE SCHEMA IF NOT EXISTS gold_db.customers;

-- New in Chapter 12: the merchant dimension the book has been joining to by
-- merchant_id since Chapter 5 without ever declaring, and the schema that
-- holds the semantic view object itself. Neither holds Chapter 5 data.
CREATE SCHEMA IF NOT EXISTS gold_db.merchants
    COMMENT = 'Gold conformed merchant dimension (introduced in Chapter 12)';
CREATE SCHEMA IF NOT EXISTS gold_db.semantic
    COMMENT = 'Chapter 12 semantic view objects only - no tables live here';

USE DATABASE gold_db;


-- =============================================================================
-- 1. Customer cohort for the Chapter 12 fixture
-- -----------------------------------------------------------------------------
-- The top-up needs a customer population large enough for customer_count to
-- mean something. These 500 rows go into the real Chapter 5 SCD Type 2
-- dimension as current versions, tagged 'CH12-SEED' in record_hash so the
-- teardown can find them again. effective_from is fixed, not
-- CURRENT_TIMESTAMP(), so the fixture is identical on every run.
-- =============================================================================

DELETE FROM gold_db.customers.dim_customers
 WHERE record_hash IN ('CH12-SEED', 'CH12-BACKFILL');

INSERT INTO gold_db.customers.dim_customers
    (customer_id, customer_name, email, address_line1,
     city, state, postal_code,
     effective_from, effective_to, is_current, record_hash)
SELECT
    'CUST-CH12-' || LPAD(seq, 4, '0')                     AS customer_id,
    ARRAY_CONSTRUCT('Ava','Liam','Noah','Emma','Mia','Lucas','Sofia','Ethan',
                    'Zoe','Owen','Ivy','Caleb','Nora','Felix','Ruby','Jonas')[
        MOD(ABS(HASH(seq, 'first')), 16)]::STRING
      || ' ' ||
    ARRAY_CONSTRUCT('Silva','Chen','Patel','Rossi','Kim','Moreau','Costa',
                    'Novak','Haddad','Okafor','Berg','Tanaka','Iqbal','Reyes',
                    'Dubois','Klein')[
        MOD(ABS(HASH(seq, 'last')), 16)]::STRING          AS customer_name,
    'customer' || LPAD(seq, 4, '0') || '@example.com'     AS email,
    (100 + MOD(ABS(HASH(seq, 'addr')), 9900)) || ' Main St' AS address_line1,
    ARRAY_CONSTRUCT('Austin','Denver','Raleigh','Boise','Madison',
                    'Tempe','Savannah','Portland','Buffalo','Fresno')[
        MOD(ABS(HASH(seq, 'geo')), 10)]::STRING           AS city,
    ARRAY_CONSTRUCT('TX','CO','NC','ID','WI',
                    'AZ','GA','OR','NY','CA')[
        MOD(ABS(HASH(seq, 'geo')), 10)]::STRING           AS state,
    LPAD(MOD(ABS(HASH(seq, 'zip')), 100000), 5, '0')      AS postal_code,
    '2025-01-01 00:00:00'::TIMESTAMP_NTZ                  AS effective_from,
    '9999-12-31'::TIMESTAMP_NTZ                           AS effective_to,
    TRUE                                                  AS is_current,
    'CH12-SEED'                                           AS record_hash
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1 AS seq
      FROM TABLE(GENERATOR(ROWCOUNT => 500)));

-- Expected: 500 rows inserted.


-- =============================================================================
-- 2. Top up the real fact table
-- -----------------------------------------------------------------------------
-- Every attribute derives from HASH of a gap-free row number plus a per-column
-- salt, which decorrelates the columns. The ROW_NUMBER wrapper matters because
-- SEQ8 alone does not guarantee a gap-free sequence, and the explicit
-- timestamp bounds hold the data to the same 18 calendar months on every run.
--
-- Amount tiers:  95% $5-$150, 4.5% $150-$1,500, 0.5% $1,500-$9,000.
-- Status split:  88% COMPLETED, 3% REFUNDED, 5% FAILED, 4% PENDING.
-- merchant_id and category are both functions of the same merchant number, so
-- a merchant keeps one category across all its payments.
--
-- The column list is explicit because the Chapter 5 table's physical order is
-- (transaction_id, customer_id, merchant_id, amount, currency, transaction_ts,
--  category, channel, status, risk_score, ingested_at) and this SELECT does
-- not follow it.
-- =============================================================================

DELETE FROM gold_db.transactions.fact_transactions
 WHERE transaction_id LIKE 'TXN-CH12-%';

INSERT INTO gold_db.transactions.fact_transactions
    (transaction_id, transaction_ts, status,
     customer_id, merchant_id, amount, currency,
     category, channel, risk_score, ingested_at)
SELECT
    'TXN-CH12-' || seq                                    AS transaction_id,
    DATEADD('minute',
            MOD(ABS(HASH(seq, 'ts')),
                DATEDIFF('minute', '2025-01-01', '2026-07-01')),
            '2025-01-01 00:00:00'::TIMESTAMP_NTZ)         AS transaction_ts,
    CASE WHEN MOD(ABS(HASH(seq, 'st')), 100) < 88 THEN 'COMPLETED'
         WHEN MOD(ABS(HASH(seq, 'st')), 100) < 91 THEN 'REFUNDED'
         WHEN MOD(ABS(HASH(seq, 'st')), 100) < 96 THEN 'FAILED'
         ELSE 'PENDING' END                               AS status,
    'CUST-CH12-' || LPAD(MOD(ABS(HASH(seq, 'cust')), 500), 4, '0')
                                                          AS customer_id,
    'MERCH-CH12-' || LPAD(MOD(ABS(HASH(seq, 'merch')), 40), 2, '0')
                                                          AS merchant_id,
    ROUND(CASE WHEN MOD(ABS(HASH(seq, 'tier')), 1000) < 950
               THEN 5    + MOD(ABS(HASH(seq, 'amt')), 14500) / 100
               WHEN MOD(ABS(HASH(seq, 'tier')), 1000) < 995
               THEN 150  + MOD(ABS(HASH(seq, 'amt')), 135000) / 100
               ELSE 1500 + MOD(ABS(HASH(seq, 'amt')), 750000) / 100
          END, 2)                                         AS amount,
    'USD'                                                 AS currency,
    ARRAY_CONSTRUCT('retail','travel','dining','software',
                    'streaming','gaming','groceries','fitness')[
        MOD(MOD(ABS(HASH(seq, 'merch')), 40), 8)]::STRING AS category,
    ARRAY_CONSTRUCT('mobile','web','POS','API')[
        MOD(ABS(HASH(seq, 'chan')), 4)]::STRING           AS channel,
    MOD(ABS(HASH(seq, 'risk')), 101)                      AS risk_score,
    '2026-07-01 00:00:00'::TIMESTAMP_NTZ                  AS ingested_at
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1 AS seq
      FROM TABLE(GENERATOR(ROWCOUNT => 50000)));

-- Expected: 50,000 rows inserted, in seconds on an X-Small warehouse.


-- =============================================================================
-- 3. Backfill the customers Chapter 5 never put in the dimension
-- -----------------------------------------------------------------------------
-- The Chapter 5 fact fixture references customer ids (CUST_FRAUD, CUST_A ...)
-- that its SCD Type 2 flow never loads into dim_customers, so a keyed
-- relationship on the real gold layer would see them as orphans. Preparing a
-- keyed slice like this is the most common work standing between an existing
-- warehouse and its first semantic view - it is the point of section 2.2, not
-- an accident of the fixture. Tagged CH12-BACKFILL so teardown reverses it.
-- =============================================================================

INSERT INTO gold_db.customers.dim_customers
    (customer_id, customer_name, email, address_line1,
     city, state, postal_code,
     effective_from, effective_to, is_current, record_hash)
SELECT DISTINCT
    f.customer_id,
    'Unmodelled Chapter 5 customer'                       AS customer_name,
    NULL                                                  AS email,
    NULL                                                  AS address_line1,
    NULL                                                  AS city,
    ARRAY_CONSTRUCT('TX','CO','NC','ID','WI',
                    'AZ','GA','OR','NY','CA')[
        MOD(ABS(HASH(f.customer_id, 'geo')), 10)]::STRING AS state,
    NULL                                                  AS postal_code,
    '2025-01-01 00:00:00'::TIMESTAMP_NTZ                  AS effective_from,
    '9999-12-31'::TIMESTAMP_NTZ                           AS effective_to,
    TRUE                                                  AS is_current,
    'CH12-BACKFILL'                                       AS record_hash
FROM gold_db.transactions.fact_transactions f
WHERE NOT EXISTS (
    SELECT 1
      FROM gold_db.customers.dim_customers d
     WHERE d.customer_id = f.customer_id
       AND d.is_current  = TRUE);

-- Expected: one row per Chapter 5 customer id missing from the dimension
-- (9 with the stock Chapter 5 fixture, 0 if you already conformed it).


-- =============================================================================
-- 4. The keyed current slice of the customer dimension
-- -----------------------------------------------------------------------------
-- dim_customers keeps SCD Type 2 history, so customer_id repeats across
-- versions and cannot key a relationship. Filtering to the current slice
-- restores one row per customer. Chapter 12 owns this view; teardown drops it.
-- =============================================================================

CREATE OR REPLACE VIEW gold_db.customers.dim_customers_current
    COMMENT = 'Current SCD2 slice of dim_customers, one row per customer'
AS
SELECT customer_id,
       customer_name,
       email,
       address_line1,
       city,
       state,
       postal_code
  FROM gold_db.customers.dim_customers
 WHERE is_current = TRUE;


-- =============================================================================
-- 5. The conformed merchant dimension
-- -----------------------------------------------------------------------------
-- Built from the merchant ids actually present in the fact table, so it covers
-- the Chapter 5 merchants and the Chapter 12 cohort in one pass and cannot
-- produce an orphan. merchant_category comes from the category the merchant's
-- own payments carry, which is why the top-up derives category from the
-- merchant number rather than from seq.
-- =============================================================================

CREATE OR REPLACE TABLE gold_db.merchants.dim_merchants (
    merchant_id       STRING NOT NULL,
    merchant_name     STRING,
    merchant_category STRING,
    merchant_city     STRING
);

INSERT INTO gold_db.merchants.dim_merchants
    (merchant_id, merchant_name, merchant_category, merchant_city)
SELECT
    merchant_id,
    INITCAP(REPLACE(REPLACE(merchant_id, '_', ' '), '-', ' '))  AS merchant_name,
    LOWER(NVL(MAX(category), 'retail'))                         AS merchant_category,
    ARRAY_CONSTRUCT('Austin','Denver','Raleigh','Boise','Madison',
                    'Tempe','Savannah','Portland','Buffalo','Fresno')[
        MOD(ABS(HASH(merchant_id, 'mcity')), 10)]::STRING       AS merchant_city
FROM gold_db.transactions.fact_transactions
GROUP BY merchant_id;

-- Expected: 47 rows with the stock fixture (40 Chapter 12 + 7 Chapter 5).


-- =============================================================================
-- 6. The refund event table
-- -----------------------------------------------------------------------------
-- One row per refund event, many per payment. This is the second grain the
-- semantic view spans: a payment can be refunded more than once, so refunds
-- cannot be a column on the payment. One or two events per REFUNDED payment,
-- together returning 50 to 100 percent of the captured amount.
-- =============================================================================

CREATE OR REPLACE TABLE gold_db.transactions.fact_refunds (
    refund_id      STRING        NOT NULL,
    transaction_id STRING        NOT NULL,
    refund_amount  NUMBER(12,2)  NOT NULL,
    refund_ts      TIMESTAMP_NTZ NOT NULL,
    refund_reason  STRING
);

INSERT INTO gold_db.transactions.fact_refunds
    (refund_id, transaction_id, refund_amount, refund_ts, refund_reason)
WITH refunded AS (
    SELECT transaction_id,
           transaction_ts,
           ROUND(amount * (50 + MOD(ABS(HASH(transaction_id, 'pct')), 51))
                 / 100, 2)                                AS total_refund,
           1 + MOD(ABS(HASH(transaction_id, 'n')), 2)      AS event_count
      FROM gold_db.transactions.fact_transactions
     WHERE status = 'REFUNDED'
       AND transaction_id LIKE 'TXN-CH12-%'
),
events AS (
    SELECT r.*, e.idx
      FROM refunded r
     CROSS JOIN (SELECT 1 AS idx UNION ALL SELECT 2 AS idx) e
     WHERE e.idx <= r.event_count
)
SELECT
    'RFD-CH12-' || SUBSTR(transaction_id, 10) || '-' || idx AS refund_id,
    transaction_id,
    CASE WHEN event_count = 1 THEN total_refund
         WHEN idx = 1         THEN ROUND(total_refund * 0.6, 2)
         ELSE total_refund - ROUND(total_refund * 0.6, 2)
    END                                                     AS refund_amount,
    DATEADD('day',
            idx + MOD(ABS(HASH(transaction_id, 'rts')), 14),
            transaction_ts)                                 AS refund_ts,
    ARRAY_CONSTRUCT('customer request','duplicate charge',
                    'item returned','chargeback')[
        MOD(ABS(HASH(transaction_id, 'why')), 4)]::STRING    AS refund_reason
FROM events;

-- Expected: roughly 2,250 rows (about 1,500 REFUNDED payments, 1.5 events each).


-- =============================================================================
-- 7. Prove the keys before building on them
-- -----------------------------------------------------------------------------
-- A semantic view's PRIMARY KEY declarations are assertions, not constraints:
-- Snowflake stores them as metadata and does not enforce them, so a duplicate
-- or null key surfaces later as silently inflated joins. The chapter quotes an
-- eight-column version of this query; the version below adds the null checks
-- on every key column.
-- =============================================================================

SELECT
  (SELECT COUNT(*) - COUNT(DISTINCT transaction_id)
     FROM gold_db.transactions.fact_transactions)                AS dup_txns,
  (SELECT COUNT(*) - COUNT(transaction_id)
     FROM gold_db.transactions.fact_transactions)                AS null_txns,
  (SELECT COUNT(*) - COUNT(DISTINCT customer_id)
     FROM gold_db.customers.dim_customers_current)               AS dup_customers,
  (SELECT COUNT(*) - COUNT(customer_id)
     FROM gold_db.customers.dim_customers_current)               AS null_customers,
  (SELECT COUNT(*) - COUNT(DISTINCT merchant_id)
     FROM gold_db.merchants.dim_merchants)                       AS dup_merchants,
  (SELECT COUNT(*) - COUNT(merchant_id)
     FROM gold_db.merchants.dim_merchants)                       AS null_merchants,
  (SELECT COUNT(*) - COUNT(DISTINCT refund_id)
     FROM gold_db.transactions.fact_refunds)                     AS dup_refunds,
  (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions f
     LEFT JOIN gold_db.customers.dim_customers_current c
       ON f.customer_id = c.customer_id
    WHERE c.customer_id IS NULL)                                 AS customer_orphans,
  (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions f
     LEFT JOIN gold_db.merchants.dim_merchants m
       ON f.merchant_id = m.merchant_id
    WHERE m.merchant_id IS NULL)                                 AS merchant_orphans,
  (SELECT COUNT(*) FROM gold_db.transactions.fact_refunds r
     LEFT JOIN gold_db.transactions.fact_transactions f
       ON r.transaction_id = f.transaction_id
    WHERE f.transaction_id IS NULL)                              AS refund_orphans;

-- Expected: zero in every column. Any nonzero value means the preparation is
-- incomplete, and the semantic view would faithfully report wrong joins on top
-- of it. Run chapter12_2_create_view.sql next.
