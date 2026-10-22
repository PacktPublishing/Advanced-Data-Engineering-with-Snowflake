-- =============================================================================
-- Chapter 12: Teardown
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Reverses chapter12_0_setup.sql exactly and leaves the Chapter 5 gold layer
-- as it was. Run this before returning to an earlier chapter's examples: while
-- the Chapter 12 rows are present, Chapter 5, 6, and 9 examples that quote row
-- counts or totals return different numbers.
--
-- Removes the one-tool revenue agent before its backing view and schema.
-- Reversibility contract:
--   fact_transactions - every Chapter 12 row carries a 'TXN-CH12-' prefix on
--                       transaction_id, so a targeted DELETE reverses the
--                       top-up without touching Chapter 5 rows.
--   dim_customers     - every Chapter 12 row carries record_hash 'CH12-SEED'
--                       (the fixture cohort) or 'CH12-BACKFILL' (customers the
--                       Chapter 5 fact referenced but its dimension never had).
--   everything else   - chapter-owned objects, dropped outright.
--
-- There is NO DROP SCHEMA ... CASCADE here. gold_db.transactions and
-- gold_db.customers are shared with earlier chapters, and the two schemas
-- Chapter 12 does own are dropped with RESTRICT so the statement fails loudly
-- if anything unexpected is still inside them.
--
-- Role convention: SYSADMIN, or any role with DELETE on the two shared tables
-- and OWNERSHIP on the chapter-owned objects.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;

-- 1. The revenue agent, its semantic view, then their chapter-owned schema.
DROP AGENT IF EXISTS gold_db.semantic.techflow_revenue_agent;
DROP SEMANTIC VIEW IF EXISTS gold_db.semantic.techflow_revenue;
DROP SCHEMA IF EXISTS gold_db.semantic RESTRICT;

-- 2. The refund grain, the keyed customer slice, and the merchant dimension.
DROP TABLE IF EXISTS gold_db.transactions.fact_refunds;
DROP VIEW  IF EXISTS gold_db.customers.dim_customers_current;
DROP TABLE IF EXISTS gold_db.merchants.dim_merchants;
DROP SCHEMA IF EXISTS gold_db.merchants RESTRICT;

-- 3. The rows Chapter 12 wrote into the two shared Chapter 5 tables.
DELETE FROM gold_db.transactions.fact_transactions
 WHERE transaction_id LIKE 'TXN-CH12-%';

DELETE FROM gold_db.customers.dim_customers
 WHERE record_hash IN ('CH12-SEED', 'CH12-BACKFILL');

-- 4. Verify Chapter 5 is back to where it started.
SELECT
  (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions)   AS fact_rows,
  (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions
    WHERE transaction_id LIKE 'TXN-CH12-%')                       AS ch12_fact_rows,
  (SELECT COUNT(*) FROM gold_db.customers.dim_customers)          AS dim_rows,
  (SELECT COUNT(*) FROM gold_db.customers.dim_customers
    WHERE record_hash IN ('CH12-SEED','CH12-BACKFILL'))           AS ch12_dim_rows;

-- Expected: ch12_fact_rows = 0 and ch12_dim_rows = 0. fact_rows returns to the
-- Chapter 5 count (19 with the stock chapter5_1 fixture) and dim_rows to
-- whatever your Chapter 5 SCD Type 2 run left behind.
