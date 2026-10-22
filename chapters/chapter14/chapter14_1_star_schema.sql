-- =============================================================================
-- Chapter 14: Data Modeling in Snowflake using AI-Assisted Practices
-- Section 2: Building and optimizing the TechFlow star schema
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 2.1 Building the date dimension, 2.2 Declaring keys for join
-- elimination, 2.3 Verifying the star end to end. Runs standalone top to
-- bottom once chapter14_0_setup.sql has run. Independent of the other section
-- files.
--
-- Run once: the constraint block in 2.2 adds pk_dim_merchants, pk_dim_date and
-- fk_txn_merchant, and a second ADD of the same constraint name fails. To run
-- the file again, run chapter14_teardown.sql first (it drops the three
-- constraints and resets pk_fact_transactions to NORELY).
--
-- Prerequisites: chapter14_0_setup.sql (which verifies the Chapter 5 and
-- Chapter 12 gold layer is present).
--
-- Role convention: SYSADMIN. The ALTER TABLE statements need OWNERSHIP of
-- gold_db.transactions.fact_transactions and gold_db.merchants.dim_merchants,
-- which SYSADMIN holds when the earlier chapters ran as SYSADMIN (Chapter 5
-- ran as ACCOUNTADMIN in its setup; if the ALTER fails with an ownership
-- error, run this file as the role that owns the table).
--
-- Placeholder convention: <REPLACE: ...>. This file has none.
--
-- Reversibility: teardown drops gold_db.calendar (pk_dim_date goes with its
-- table), the star view, pk_dim_merchants and fk_txn_merchant by name, and
-- resets pk_fact_transactions to NORELY.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- =============================================================================
-- 2.1 Building the date dimension
-- -----------------------------------------------------------------------------
-- One row per day for 2025 through 2027: the two seeded years plus a year of
-- headroom, because the Chapter 5 fixture stamps its rows with the load time
-- and a calendar that ends before the data does drops rows from every inner
-- join. The key is the DATE itself; integer yyyymmdd keys serve index-era
-- warehouses and only add a translation step here.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS gold_db.calendar;

CREATE OR REPLACE TABLE gold_db.calendar.dim_date AS
SELECT d                          AS date_day,
       YEAR(d)                    AS year,
       QUARTER(d)                 AS quarter,
       MONTH(d)                   AS month,
       MONTHNAME(d)               AS month_name,
       DATE_TRUNC('month', d)     AS month_start,
       DAYNAME(d)                 AS day_name,
       DAYOFWEEKISO(d)            AS day_of_week_iso,
       DAYOFWEEKISO(d) >= 6       AS is_weekend
FROM (
    SELECT DATEADD('day', seq, '2025-01-01'::DATE) AS d
    FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1 AS seq
          FROM TABLE(GENERATOR(ROWCOUNT => 1095)))
);

-- Expected: 'Table DIM_DATE successfully created.'

-- Fiscal calendar variant (commented, reader-specific). A fiscal year that
-- starts in April adds two derived columns to the SELECT above:
--   YEAR(DATEADD('month', 9, d))              AS fiscal_year,
--   MOD(MONTH(d) + 8, 12) + 1                 AS fiscal_period
-- Replace the 9 with 13 minus your start month and the 8 with 12 minus it
-- (April: 13 - 4 = 9 and 12 - 4 = 8; July: 6 and 5).

COMMENT ON TABLE gold_db.calendar.dim_date IS
    'One row per calendar day, 2025-01-01 through 2027-12-31. Conformed date dimension; extend ROWCOUNT to outlive 2027.';

-- Verify the span before anything joins to it.
SELECT COUNT(*)      AS days,
       MIN(date_day) AS first_day,
       MAX(date_day) AS last_day
FROM gold_db.calendar.dim_date;

-- Expected: one row, 1095 days, 2025-01-01 to 2027-12-31.


-- =============================================================================
-- 2.2 Declaring keys for join elimination
-- -----------------------------------------------------------------------------
-- Step 1: re-run the Chapter 12 key tests. RELY is a promise Snowflake does not
-- check, so the keys qualify for the property here, before it is declared. The
-- version below is the full ten-column form from chapter12_0_setup.sql, kept
-- in a temporary table so the guard block after it can read the result.
-- =============================================================================

CREATE OR REPLACE TEMPORARY TABLE gold_db.calendar.key_tests_tmp AS
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

SELECT * FROM gold_db.calendar.key_tests_tmp;

-- Expected: zero in every column. Do not declare RELY on a key that fails here.

-- Step 2: declare the keys, gated by step 1. The chapter runs the four ALTER
-- statements from the worksheet after reading the key tests; this file keeps
-- them inside the guard block, so a nonzero key test raises before any RELY is
-- declared whatever the client does after an error (SnowSQL continues past
-- errors by default; Snowsight and snow sql stop).
--
-- fact_transactions has carried pk_fact_transactions since Chapter 5, so it
-- only gets the trust added (MODIFY CONSTRAINT); the merchant dimension and the
-- calendar get primary keys, plus the one foreign key the star can truthfully
-- promise. No key on fact_transactions.customer_id: the customer dimension
-- keeps Type 2 history, so customer_id is not unique there, and the
-- current-slice view cannot hold a constraint.
EXECUTE IMMEDIATE $$
DECLARE
    failing_total NUMBER;
    dirty_key EXCEPTION (-20015, 'A key test returned a nonzero count. Fix the key before declaring RELY on it.');
BEGIN
    SELECT dup_txns + null_txns + dup_customers + null_customers
         + dup_merchants + null_merchants + dup_refunds
         + customer_orphans + merchant_orphans + refund_orphans
      INTO :failing_total
      FROM gold_db.calendar.key_tests_tmp;
    IF (failing_total > 0) THEN
        RAISE dirty_key;
    END IF;

    ALTER TABLE gold_db.transactions.fact_transactions
        MODIFY CONSTRAINT pk_fact_transactions RELY;

    ALTER TABLE gold_db.merchants.dim_merchants
        ADD CONSTRAINT pk_dim_merchants
        PRIMARY KEY (merchant_id) RELY;

    ALTER TABLE gold_db.calendar.dim_date
        ADD CONSTRAINT pk_dim_date
        PRIMARY KEY (date_day) RELY;

    ALTER TABLE gold_db.transactions.fact_transactions
        ADD CONSTRAINT fk_txn_merchant
        FOREIGN KEY (merchant_id)
        REFERENCES gold_db.merchants.dim_merchants (merchant_id) RELY;

    RETURN 'Every key test returned zero. Four constraints now carry RELY.';
END;
$$;

-- Expected: 'Every key test returned zero. Four constraints now carry RELY.'
-- A -20015 error means a key test failed and nothing was declared; the SELECT
-- above shows which column. An 'already exists' error means the block ran
-- before: run chapter14_teardown.sql, then this file again.

-- Confirm what the account now states about the keys. SHOW PRIMARY KEYS does
-- not report the RELY property; the TABLE_CONSTRAINTS view and GET_DDL do.
SELECT table_schema, table_name, constraint_name, constraint_type, rely
  FROM gold_db.information_schema.table_constraints
 WHERE constraint_name IN ('PK_FACT_TRANSACTIONS', 'PK_DIM_MERCHANTS',
                           'PK_DIM_DATE', 'FK_TXN_MERCHANT')
 ORDER BY table_schema, table_name, constraint_type;

-- Expected: four rows, rely = YES on each (the view stores the property as the
-- strings YES and NO, not as a boolean; Snowflake's own BCR-1902 query uses
-- WHERE RELY = 'YES'). GET_DDL('TABLE', 'gold_db.merchants.dim_merchants')
-- shows the same property inline as 'PRIMARY KEY (MERCHANT_ID) RELY'.


-- =============================================================================
-- 2.3 Verifying the star end to end
-- -----------------------------------------------------------------------------
-- The star view joins the fact to the calendar and the merchant dimension only.
-- The customer path stays out: its correct join depends on the history policy
-- settled in section 3. The date join derives transaction_ts::DATE on the fact
-- side, which is why that path carries no foreign key.
-- =============================================================================

CREATE OR REPLACE VIEW gold_db.transactions.star_transactions AS
SELECT ft.transaction_id, ft.transaction_ts, ft.status,
       ft.amount, ft.channel, ft.customer_id,
       dd.month_start, dd.month_name, dd.is_weekend,
       m.merchant_id, m.merchant_category, m.merchant_city
FROM gold_db.transactions.fact_transactions ft
JOIN gold_db.calendar.dim_date dd
  ON dd.date_day = ft.transaction_ts::DATE
JOIN gold_db.merchants.dim_merchants m
  ON m.merchant_id = ft.merchant_id;

-- Expected: 'View STAR_TRANSACTIONS successfully created.'

-- The view must not lose rows: the calendar span and the merchant keys were
-- both verified above, so the two counts agree. The view recomputes both
-- joins on every query; when a consumer needs the flattened star to answer
-- faster than the joins allow, materialize it as a dynamic table with a
-- target lag (the Chapter 9 pattern). The key declarations and the table
-- format decision are independent of that choice.
SELECT (SELECT COUNT(*) FROM gold_db.transactions.star_transactions) AS star_transactions_rows,
       (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions) AS fact_transactions_rows;

-- Expected: identical counts (50,024 with the stock Chapter 5 + 12 fixtures).

-- Query the star the way a dashboard would: no join logic, no date derivation.
-- The status expression stays in the query, since the view exposes every status
-- and the aggregation decides which count as captured. (The chapter describes
-- this query; the block is here for the reader who wants to run it.)
SELECT month_start, merchant_category,
       SUM(IFF(status IN ('COMPLETED', 'REFUNDED'), amount, 0))
           AS captured_amount
FROM gold_db.transactions.star_transactions
GROUP BY month_start, merchant_category
ORDER BY month_start, captured_amount DESC;

-- Expected: one row per month and category pairing across the seeded months.

-- Watch join elimination work. The query touches no merchant column, the join
-- runs on a RELY foreign key, so the optimizer drops dim_merchants from the
-- plan. dim_date stays: its join is an expression the optimizer cannot prove
-- lossless. The second statement reads the table list straight from the plan.
EXPLAIN SELECT channel, SUM(amount)
FROM gold_db.transactions.star_transactions
GROUP BY channel;

SELECT "operation", "objects"
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
 WHERE "objects" IS NOT NULL;

-- Expected: two TableScan rows, GOLD_DB.TRANSACTIONS.FACT_TRANSACTIONS and
-- GOLD_DB.CALENDAR.DIM_DATE; no row for DIM_MERCHANTS. (Verified on a live
-- account 2026-10-09.)


-- =============================================================================
-- Section 2 validation set
-- =============================================================================

SELECT 'calendar_days'  AS check_name,
       COUNT(*) = 1095   AS passed
  FROM gold_db.calendar.dim_date
UNION ALL
SELECT 'star_keeps_every_fact_row',
       (SELECT COUNT(*) FROM gold_db.transactions.star_transactions)
       = (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions)
UNION ALL
SELECT 'merchant_pk_declared_with_rely',
       COUNT(*) = 1
  FROM gold_db.information_schema.table_constraints
 WHERE table_schema = 'MERCHANTS'
   AND table_name   = 'DIM_MERCHANTS'
   AND constraint_type = 'PRIMARY KEY'
   AND rely = 'YES'
UNION ALL
SELECT 'fact_fk_declared_with_rely',
       COUNT(*) = 1
  FROM gold_db.information_schema.table_constraints
 WHERE table_schema = 'TRANSACTIONS'
   AND table_name   = 'FACT_TRANSACTIONS'
   AND constraint_type = 'FOREIGN KEY'
   AND rely = 'YES';

-- Expected: four rows, every passed = TRUE. Run chapter14_2_scd_patterns.sql next.
