-- =============================================================================
-- Chapter 12: Semantic Layer and Semantic Views - Section 4
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 4.1 Understanding How an Agent Consumes the View, 4.2
-- Improving Answers with Synonyms, Instructions, and Verified Queries, 4.3
-- Round-Tripping the YAML Specification. The promotion template is at the end
-- of this file.
--
-- Prerequisites: chapter12_0_setup.sql and chapter12_2_create_view.sql have
-- run. A region where Snowflake Cortex is available, or cross-region inference
-- enabled, and chapter12_3_query_view.sql has created TECHFLOW_REVENUE_AGENT
-- for the agent Preview steps. Use the default role and warehouse described
-- in that file. SQL/YAML-only work does not require a running agent.
--
-- Role convention: SYSADMIN for the DDL and the grants; the GRANT block near
-- the end needs a role that can grant on gold_db, which SYSADMIN has as owner.
--
-- Placeholder convention: <REPLACE: ...> marks values you must substitute.
-- These occur only in the promotion template at the end.
--
-- The chapter applies the instruction, sample values, and verified query in
-- the Snowsight semantic view editor. Every one of those fields is also a DDL
-- clause, so a code-first team never opens the editor - that is what the
-- statement below is. Apply it INSTEAD of the editor steps, or after them to
-- put the same state under version control.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- -----------------------------------------------------------------------------
-- 4.2 The editor fields as DDL
-- AGENT PREVIEW BASELINE AND RETEST (section 4.2, UI actions)
-- Before applying the DDL below or editing the view in Snowsight, open a NEW
-- thread on the TECHFLOW_REVENUE_AGENT Preview tab, ask "What was total
-- revenue by month?", and save the SQL from the trace. After saving the changes,
-- ask again in another new thread. Verify that transaction_month is
-- bounded to the last 12 complete months. If not, tighten the instruction and
-- retest. Instructions steer generation; record the result, not an assumed PASS.
-- The verified query uses CURRENT_DATE so its bounds follow the same rolling
-- default as the instruction. Fixed fixture dates would override that intent.
--
-- -----------------------------------------------------------------------------
-- Three additions to the stage-2 definition: SAMPLE_VALUES and IS_ENUM on the
-- two closed-vocabulary dimensions, the AI_SQL_GENERATION instruction, and one
-- AI_VERIFIED_QUERIES entry.
--
-- Ordering rules Snowflake enforces: COMMENT precedes the AI_ clauses, and
-- within a dimension SAMPLE_VALUES precedes IS_ENUM. IS_ENUM is valid on
-- dimensions only, never on facts.
--
-- Sample values are stored as plain metadata on the view and are NOT covered
-- by masking policies on the underlying columns. Never add sample values to a
-- dimension that carries sensitive data. customer_state is deliberately left
-- without them for that reason.
--
-- The verified query covers the last 12 complete calendar months. The fixture
-- ends at June 2026, so later executions can return fewer populated months.
-- Do not replace the rolling bounds with fixture dates: that changes the default.
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
      COMMENT = 'High-value share of completed gross revenue'
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

-- Expected: Statement executed successfully. Re-run the stage-2 validation set
-- in chapter12_2_create_view.sql: metadata changes must not move a number.


-- -----------------------------------------------------------------------------
-- 4.3 step 1: export the view to YAML
-- -----------------------------------------------------------------------------
-- READ_YAML is a FUNCTION. The result is the artifact you commit to Git, so
-- reviewers diff metric expressions in a pull request instead of reading
-- GET_DDL output. After any editor change, re-export, diff against Git, and
-- treat a difference as a broken build until one side is corrected.
-- -----------------------------------------------------------------------------

SELECT SYSTEM$READ_YAML_FROM_SEMANTIC_VIEW(
    'gold_db.semantic.techflow_revenue');

-- Expected: a YAML document whose keys correspond to the DDL concepts
-- (tables, relationships, per-table dimensions, facts, and metrics), with the
-- sample values appearing as a sample_values property. The nesting differs
-- from the DDL's flat clause order. Save the output over techflow_revenue.yaml
-- in this directory.


-- -----------------------------------------------------------------------------
-- 4.3 step 2: the reverse direction
-- -----------------------------------------------------------------------------
-- CREATE_FROM_YAML is a STORED PROCEDURE, not a function. It serves two jobs:
-- promoting a reviewed file from Git into another environment, and migrating a
-- legacy Cortex Analyst YAML model into a governed object. Pass TRUE as the
-- third argument first, which validates the YAML without creating anything.
-- -----------------------------------------------------------------------------

-- CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
--     'gold_db.semantic',
--     $$name: techflow_revenue
-- tables:
--   ...$$);
--
-- The $$...$$ block above is the chapter's illustrative shape, not a runnable
-- document - paste a real export over it before executing. For a migration,
-- pass the staged file's contents and compare the created view's DESCRIBE
-- output against the original before retiring the stage copy.


-- =============================================================================
-- PROMOTION TEMPLATE - not runnable as written
-- -----------------------------------------------------------------------------
-- Substitute both placeholders before executing. Pairs with the Chapter 10
-- CI/CD flow: the YAML lives in Git, the validation-only call gates the pull
-- request, and the pipeline applies the reviewed file.
-- =============================================================================

-- Step 1: validate the reviewed YAML WITHOUT creating anything.
-- CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
--     'gold_db.semantic',
--     $$<REPLACE: contents of techflow_revenue.yaml>$$,
--     TRUE);   -- validate only

-- Step 2: create the object for real (drop the third argument).
-- CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
--     'gold_db.semantic',
--     $$<REPLACE: contents of techflow_revenue.yaml>$$);

-- Step 3: grants. A first deployment into a new environment has no view grants.
-- CREATE OR ALTER on an existing view preserves them. SQL-only consumers need
-- SELECT on the semantic view; REFERENCES is needed for definition inspection
-- and export, not for querying it.
-- GRANT SELECT ON SEMANTIC VIEW gold_db.semantic.techflow_revenue
--     TO ROLE <REPLACE: your SQL consumer role>;
--
-- For an agent consumer, create the agent in the target environment using
-- section 3.3 in chapter12_3_query_view.sql, then apply its AGENT CONSUMER GRANTS
-- block. That block includes the agent, semantic view, source objects, database,
-- schemas, warehouse, database role, and test-user defaults from Table 12.2.
-- Verify one question under a non-owner default role before enabling consumers.

-- Step 4: prove the deployed object against the metric contracts. Run the
-- final validation set in chapter12_5_coco.sql and require every row to PASS
-- before routing consumers to the new environment.
-- Run chapter12_5_coco.sql next.
