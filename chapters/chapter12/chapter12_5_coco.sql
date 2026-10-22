-- =============================================================================
-- Chapter 12: Semantic Layer and Semantic Views - Section 5
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 5. Authoring Semantic Views with Snowflake CoCo. This file is the
-- reviewed OUTCOME of the CoCo working session, not a transcript of it: the
-- refund_rate metric the agent composed, plus the validation set the chapter
-- ends with.
--
-- Prerequisites: chapter12_0_setup.sql, chapter12_2_create_view.sql, and
-- chapter12_4_agent_backing.sql have run. This statement carries forward
-- everything those files added, because CREATE OR ALTER converges the object
-- to the statement submitted and anything omitted disappears.
--
-- Role convention: SYSADMIN, or any role with CREATE SEMANTIC VIEW on
-- gold_db.semantic and USAGE on BOOK_WH.
--
-- CoCo session conventions for this directory live in AGENTS.md. Run the
-- session from this directory so they load, confirm the bundled semantic-view
-- skill appears in /skill list, and engage it with a direct prompt.
--
-- The prompt the chapter uses, for reference (the agent produces a candidate;
-- it never executes anything):
--
--   Using the DDL above, extend techflow_revenue with a refund_rate
--   metric at monthly grain: refunded amount as a share of gross
--   captured amount. Build it from the existing refunded_amount and
--   gross_captured_amount facts with DIV0. Generate the full CREATE OR
--   ALTER statement and a validation query that computes both
--   components manually. Do not execute anything.
--
-- The denominator choice matters: refund rate reads as the share of captured
-- money returned, so it divides by gross captured volume, not by net revenue,
-- which would inflate the rate. Both facts already exist, so the agent's job
-- is composition; the review checks that it composed them instead of
-- inventing new status logic.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- -----------------------------------------------------------------------------
-- The reviewed candidate: eight metrics
-- -----------------------------------------------------------------------------
-- Diff this against the GET_DDL output you pasted into the session before
-- running it. Everything must survive: tables, relationships, variables,
-- facts, dimensions, metrics, comments, synonyms, sample values and enum
-- flags, the custom instruction, and the verified queries. Dropping elements
-- is the characteristic failure when any tool regenerates a whole definition,
-- and CREATE OR ALTER does not rescue you: the verb keeps your grants, but
-- nothing keeps an element the statement forgets.
--
-- Tags are the exception. CREATE OR ALTER cannot add or change them and
-- preserves any that exist, so no TAG clause appears here.
-- -----------------------------------------------------------------------------

CREATE OR ALTER SEMANTIC VIEW gold_db.semantic.techflow_revenue
  TABLES (
    transactions AS gold_db.transactions.fact_transactions
      PRIMARY KEY (transaction_id)
      WITH SYNONYMS ('payments', 'sales')
      COMMENT = 'One row per payment attempt, all statuses',
    refunds AS gold_db.transactions.fact_refunds
      PRIMARY KEY (refund_id)
      COMMENT = 'One row per refund event, many per payment',
    customers AS gold_db.customers.dim_customers_current
      PRIMARY KEY (customer_id)
      COMMENT = 'Current attributes for each customer',
    merchants AS gold_db.merchants.dim_merchants
      PRIMARY KEY (merchant_id)
      COMMENT = 'One row per merchant with category and city'
  )
  RELATIONSHIPS (
    txn_to_customer AS
      transactions (customer_id) REFERENCES customers,
    txn_to_merchant AS
      transactions (merchant_id) REFERENCES merchants,
    refund_to_txn AS
      refunds (transaction_id) REFERENCES transactions
  )
  VARIABLES (
    high_value_threshold NUMBER DEFAULT 500
      COMMENT = 'Minimum completed amount to count as high-value'
  )
  FACTS (
    PRIVATE refunds.refund_amount AS refund_amount
      COMMENT = 'Refund event amount, USD',
    transactions.gross_captured_amount AS
      IFF(status IN ('COMPLETED', 'REFUNDED'), amount, 0)
      COMMENT = 'Captured amount: completed and refunded payments, USD',
    transactions.refunded_amount AS
      ZEROIFNULL(SUM(refunds.refund_amount))
      COMMENT = 'Total returned against this payment, USD',
    transactions.net_amount AS
      IFF(status IN ('COMPLETED', 'REFUNDED'), amount, 0)
        - ZEROIFNULL(SUM(refunds.refund_amount))
      COMMENT = 'Captured amount minus refunds, USD'
  )
  DIMENSIONS (
    transactions.transaction_month AS
        DATE_TRUNC('month', transaction_ts)
      WITH SYNONYMS ('month')
      COMMENT = 'Calendar month of the payment',
    transactions.channel AS channel
      WITH SYNONYMS ('platform', 'device type')
      COMMENT = 'Origin of the payment: mobile, web, POS, or API'
      SAMPLE_VALUES ('mobile', 'web', 'POS', 'API')
      IS_ENUM,
    transactions.status AS status
      COMMENT = 'Payment lifecycle state'
      SAMPLE_VALUES ('COMPLETED', 'REFUNDED', 'FAILED', 'PENDING')
      IS_ENUM,
    customers.customer_state AS state
      COMMENT = 'Customer billing state',
    merchants.merchant_category AS merchant_category
      WITH SYNONYMS ('merchant type', 'vertical')
      COMMENT = 'Merchant industry category'
  )
  METRICS (
    transactions.total_revenue AS SUM(net_amount)
      WITH SYNONYMS ('revenue', 'net revenue', 'sales total')
      COMMENT = 'Captured payments net of refunds, USD',
    transactions.transaction_count AS COUNT(transaction_id)
      COMMENT = 'Number of payment attempts, all statuses',
    transactions.average_transaction_value AS
        AVG(IFF(status = 'COMPLETED', amount, NULL))
      WITH SYNONYMS ('average ticket', 'ATV')
      COMMENT = 'Mean completed payment amount, USD',
    transactions.customer_count AS
      COUNT(DISTINCT IFF(status IN ('COMPLETED', 'REFUNDED'),
                         customer_id, NULL))
      WITH SYNONYMS ('active customers')
      COMMENT = 'Distinct customers with at least one captured payment',
    transactions.revenue_running_total AS
      SUM(total_revenue) OVER (
        PARTITION BY EXCLUDING transactions.transaction_month
        ORDER BY transactions.transaction_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      WITH SYNONYMS ('cumulative revenue')
      COMMENT = 'Running total of net revenue ordered by month',
    transactions.high_value_revenue AS
      SUM(IFF(status = 'COMPLETED' AND amount >= high_value_threshold,
              amount, 0))
      COMMENT = 'Completed gross revenue at or above the threshold, USD',
    transactions.high_value_revenue_share AS
      DIV0(SUM(IFF(status = 'COMPLETED' AND amount >= high_value_threshold,
                   amount, 0)),
           SUM(IFF(status = 'COMPLETED', amount, 0)))
      COMMENT = 'High-value share of completed gross revenue',
    transactions.refund_rate AS
      DIV0(SUM(refunded_amount), SUM(gross_captured_amount))
      WITH SYNONYMS ('refund share', 'return rate')
      COMMENT = 'Refunded amount as a share of gross captured amount'
  )
  COMMENT = 'TechFlow payments semantic model, revenue owned by finance'
  AI_SQL_GENERATION 'Revenue always means captured payments net of refunds, in USD. When a question does not specify a time range, default to the last 12 complete months.'
  AI_VERIFIED_QUERIES (
    monthly_total_revenue AS (
      QUESTION 'What was total revenue by month?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(
             gold_db.semantic.techflow_revenue
             METRICS total_revenue
             DIMENSIONS transaction_month
             WHERE transaction_month >=
               DATEADD(''month'', -12, DATE_TRUNC(''month'', CURRENT_DATE()))
               AND transaction_month < DATE_TRUNC(''month'', CURRENT_DATE())
           ) ORDER BY transaction_month'
    )
  );

-- Expected: Statement executed successfully. The view now carries four facts (one private),
-- five dimensions, eight metrics, one variable, one instruction, and one
-- verified query.


-- -----------------------------------------------------------------------------
-- Final validation set: the eight metrics the chapter ends with
-- -----------------------------------------------------------------------------
-- Every metric side must match its manual side, the same bar every metric in
-- this chapter has had to clear. The window metric is checked separately in
-- chapter12_2_create_view.sql and is unchanged by this statement.
-- -----------------------------------------------------------------------------

WITH metric AS (
    SELECT total_revenue, transaction_count, average_transaction_value,
           customer_count, high_value_revenue, high_value_revenue_share,
           refund_rate
      FROM SEMANTIC_VIEW(gold_db.semantic.techflow_revenue
                         METRICS total_revenue,
                                 transaction_count,
                                 average_transaction_value,
                                 customer_count,
                                 high_value_revenue,
                                 high_value_revenue_share,
                                 refund_rate)
),
manual AS (
    SELECT
        (SELECT SUM(IFF(status IN ('COMPLETED', 'REFUNDED'), amount, 0))
           FROM gold_db.transactions.fact_transactions)
      - (SELECT SUM(refund_amount)
           FROM gold_db.transactions.fact_refunds)              AS total_revenue,
        (SELECT COUNT(*)
           FROM gold_db.transactions.fact_transactions)          AS transaction_count,
        (SELECT AVG(amount)
           FROM gold_db.transactions.fact_transactions
          WHERE status = 'COMPLETED')                            AS average_transaction_value,
        (SELECT COUNT(DISTINCT customer_id)
           FROM gold_db.transactions.fact_transactions
          WHERE status IN ('COMPLETED', 'REFUNDED'))             AS customer_count,
        (SELECT SUM(amount)
           FROM gold_db.transactions.fact_transactions
          WHERE status = 'COMPLETED' AND amount >= 500)          AS high_value_revenue,
        (SELECT DIV0(SUM(IFF(amount >= 500, amount, 0)), SUM(amount))
           FROM gold_db.transactions.fact_transactions
          WHERE status = 'COMPLETED')                            AS high_value_revenue_share,
        DIV0((SELECT SUM(refund_amount)
                FROM gold_db.transactions.fact_refunds),
             (SELECT SUM(IFF(status IN ('COMPLETED','REFUNDED'), amount, 0))
                FROM gold_db.transactions.fact_transactions))    AS refund_rate
)
SELECT 'total_revenue' AS metric_name,
       IFF(ROUND(metric.total_revenue, 2) = ROUND(manual.total_revenue, 2),
           'PASS', 'FAIL') AS result FROM metric, manual
UNION ALL SELECT 'transaction_count',
       IFF(metric.transaction_count = manual.transaction_count, 'PASS', 'FAIL')
  FROM metric, manual
UNION ALL SELECT 'average_transaction_value',
       IFF(ROUND(metric.average_transaction_value, 2)
           = ROUND(manual.average_transaction_value, 2), 'PASS', 'FAIL')
  FROM metric, manual
UNION ALL SELECT 'customer_count',
       IFF(metric.customer_count = manual.customer_count, 'PASS', 'FAIL')
  FROM metric, manual
UNION ALL SELECT 'high_value_revenue',
       IFF(ROUND(metric.high_value_revenue, 2)
           = ROUND(manual.high_value_revenue, 2), 'PASS', 'FAIL')
  FROM metric, manual
UNION ALL SELECT 'high_value_revenue_share',
       IFF(ROUND(metric.high_value_revenue_share, 6)
           = ROUND(manual.high_value_revenue_share, 6), 'PASS', 'FAIL')
  FROM metric, manual
UNION ALL SELECT 'refund_rate',
       IFF(ROUND(metric.refund_rate, 6) = ROUND(manual.refund_rate, 6),
           'PASS', 'FAIL')
  FROM metric, manual;

-- Expected: 7 rows, all PASS. With the window contract in
-- chapter12_2_create_view.sql that is 8 of 8 metrics under contract.
-- Run chapter12_teardown.sql when you are finished with the chapter.
