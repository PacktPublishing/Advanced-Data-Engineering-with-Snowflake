-- =============================================================================
-- Chapter 12: Semantic Layer and Semantic Views - Section 1
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 1. Bridging Technical Schemas and Business Meaning with the
-- Semantic Layer. Reproduces the three revenue numbers the chapter opens with,
-- against your own gold layer.
--
-- Prerequisites: chapter12_0_setup.sql has run. Independent of every other
-- section file - run only this one if you are reading only section 1.
--
-- Role convention: SYSADMIN, or any role with SELECT on
-- gold_db.transactions.fact_transactions and gold_db.transactions.fact_refunds
-- and USAGE on BOOK_WH.
--
-- The three queries below re-implement, in one place, the status logic that
-- three different artifacts in earlier chapters each applied differently. They
-- read the fact tables directly rather than the Chapter 9 Dynamic Table or the
-- Chapter 6 dbt model, so this file runs whether or not you built those.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- -----------------------------------------------------------------------------
-- 1. The five components, one row
-- -----------------------------------------------------------------------------
-- Everything the three teams disagreed about decomposes into these five
-- amounts. Read them before the three totals below: each total is a different
-- subset of the same five numbers.
-- -----------------------------------------------------------------------------

SELECT
    ROUND((SELECT SUM(amount)
             FROM gold_db.transactions.fact_transactions
            WHERE status = 'COMPLETED'), 2)            AS completed_gross,
    ROUND((SELECT SUM(amount)
             FROM gold_db.transactions.fact_transactions
            WHERE status = 'REFUNDED'), 2)             AS refunded_captures,
    ROUND((SELECT SUM(refund_amount)
             FROM gold_db.transactions.fact_refunds), 2)
                                                       AS refunds_returned,
    ROUND((SELECT SUM(amount)
             FROM gold_db.transactions.fact_transactions
            WHERE status IN ('FAILED', 'PENDING')), 2) AS failed_and_pending,
    ROUND((SELECT SUM(amount)
             FROM gold_db.transactions.fact_transactions), 2)
                                                       AS all_status_gross;

-- Expected: five amounts, stable across runs because the top-up is
-- deterministic. Your figures will not match the chapter's illustrative
-- $4.31 / $4.47 / $4.72 million, which show the arithmetic of the divergence
-- rather than results from your own gold layer. The RELATIONSHIP between the
-- three totals below is what reproduces.


-- -----------------------------------------------------------------------------
-- 2. Team one: the Chapter 9 Dynamic Table definition
-- -----------------------------------------------------------------------------
-- merchant_daily_revenue_dt sums amount where status = 'COMPLETED', which
-- silently drops payments later marked REFUNDED even though most of that
-- money was kept. This is the lowest of the three numbers.
-- -----------------------------------------------------------------------------

SELECT ROUND(SUM(amount), 2) AS dashboard_revenue
  FROM gold_db.transactions.fact_transactions
 WHERE status = 'COMPLETED';


-- -----------------------------------------------------------------------------
-- 3. Team two: the finance worksheet definition
-- -----------------------------------------------------------------------------
-- All captured payments, completed and refunded, minus what was returned.
-- This is the definition the semantic view is going to encode, and the one
-- TechFlow's finance team owns.
-- -----------------------------------------------------------------------------

SELECT
    ROUND((SELECT SUM(amount)
             FROM gold_db.transactions.fact_transactions
            WHERE status IN ('COMPLETED', 'REFUNDED'))
        - (SELECT SUM(refund_amount)
             FROM gold_db.transactions.fact_refunds), 2) AS finance_revenue;


-- -----------------------------------------------------------------------------
-- 4. Team three: the Chapter 6 dbt model definition
-- -----------------------------------------------------------------------------
-- gold_customer_value sums t.amount with no status filter at all, so its total
-- carries the refunded captures AND the failed and pending attempts. This is
-- the highest of the three numbers.
-- -----------------------------------------------------------------------------

SELECT ROUND(SUM(amount), 2) AS all_status_revenue
  FROM gold_db.transactions.fact_transactions;


-- -----------------------------------------------------------------------------
-- 5. The three numbers side by side, with the gaps named
-- -----------------------------------------------------------------------------
-- Run this last. Each gap column is the specific decision one team made and
-- another did not, which is the whole argument for defining revenue once.
-- -----------------------------------------------------------------------------

WITH c AS (
    SELECT
        SUM(IFF(status = 'COMPLETED', amount, 0))                AS completed,
        SUM(IFF(status = 'REFUNDED',  amount, 0))                AS refunded_cap,
        SUM(IFF(status IN ('FAILED','PENDING'), amount, 0))      AS not_captured
      FROM gold_db.transactions.fact_transactions
),
r AS (
    SELECT SUM(refund_amount) AS returned
      FROM gold_db.transactions.fact_refunds
)
SELECT
    ROUND(c.completed, 2)                                   AS dashboard_revenue,
    ROUND(c.completed + c.refunded_cap - r.returned, 2)     AS finance_revenue,
    ROUND(c.completed + c.refunded_cap + c.not_captured, 2) AS all_status_revenue,
    ROUND(c.refunded_cap - r.returned, 2)                   AS gap_dashboard_to_finance,
    ROUND(c.not_captured + r.returned, 2)                   AS gap_finance_to_all_status
  FROM c, r;

-- Expected: one row. dashboard_revenue < finance_revenue < all_status_revenue,
-- and each gap column equals the difference between its neighbours. The three
-- teams were all right about their own question and all wrong about revenue.
