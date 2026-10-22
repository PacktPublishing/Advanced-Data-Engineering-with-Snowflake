-- =============================================================================
-- Chapter 12: Semantic Layer and Semantic Views - Section 3
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 3. Querying Semantic Views Using SQL and Natural Language. Every SQL
-- query the section quotes is here, in chapter order. Section 3.3 creates a
-- one-tool Cortex Agent, followed by the commented AGENT CONSUMER GRANTS and
-- AGENT PREVIEW WALKTHROUGH blocks.
--
-- Prerequisites: chapter12_0_setup.sql and chapter12_2_create_view.sql have
-- run, and the stage-2 validation set returned PASS on every row. Section 3.3
-- also needs Cortex Agents in the region or cross-region inference enabled.
-- Agent syntax checked against Snowflake documentation, September 2026;
-- SQL and DATA_AGENT_RUN checks passed on the book account, 2026-09-07.
-- Capture the Snowsight agent Preview screenshots separately.
-- Placeholder convention: <REPLACE: ...> in commented examples only.
--
-- Role convention: SYSADMIN, or any role with SELECT on the semantic view and
-- on the four source objects, USAGE on their database and schemas and BOOK_WH,
-- CREATE AGENT on gold_db.semantic, and SNOWFLAKE.CORTEX_USER. For agent
-- calls from Snowsight, the user default role must hold the grants and the default
-- warehouse must be BOOK_WH. A worksheet USE ROLE is not a substitute.
-- If needed, an ACCOUNTADMIN grants the database role before section 3.3:
-- GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SYSADMIN;
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- -----------------------------------------------------------------------------
-- 3.1a Monthly revenue through the SEMANTIC_VIEW clause
-- -----------------------------------------------------------------------------
-- No join, no status logic, no SUM. All three live in the view.
-- -----------------------------------------------------------------------------

SELECT *
FROM SEMANTIC_VIEW(
    gold_db.semantic.techflow_revenue
    METRICS total_revenue, transaction_count
    DIMENSIONS transaction_month
    WHERE transaction_month >= '2025-02-01'
)
ORDER BY transaction_month;

-- Expected: one row per month from February 2025 onward. 17 rows come from the
-- Chapter 12 top-up (Feb 2025 through Jun 2026). Chapter 5 seeds relative to
-- its execution date and adds a month only when that date falls outside the
-- fixture window. The book account returned 17 rows on 2026-09-07.


-- -----------------------------------------------------------------------------
-- 3.1b Revenue by merchant category and channel
-- -----------------------------------------------------------------------------
-- Physically a join to dim_merchants. The relationship supplies it, so the
-- person asking never needs to know the join exists. One SEMANTIC_VIEW call
-- can request metrics or facts, never both.
-- -----------------------------------------------------------------------------

SELECT *
FROM SEMANTIC_VIEW(
    gold_db.semantic.techflow_revenue
    METRICS total_revenue, average_transaction_value
    DIMENSIONS merchant_category, channel
)
ORDER BY total_revenue DESC
LIMIT 10;

-- Expected: up to 10 rows, one per merchant category and channel combination,
-- ordered by revenue.


-- -----------------------------------------------------------------------------
-- 3.1c The validation contract from section 2.5
-- -----------------------------------------------------------------------------
-- The metric on one side, a hand-written aggregation on the other. The manual
-- side joins the two grains itself, subtracting the refund table's total from
-- the payment table's captured total. Write it from the business definition,
-- not by copying the view's DDL, or the comparison proves nothing.
-- -----------------------------------------------------------------------------

SELECT
    (SELECT total_revenue
     FROM SEMANTIC_VIEW(gold_db.semantic.techflow_revenue
                        METRICS total_revenue))          AS metric_value,
    (SELECT SUM(IFF(status IN ('COMPLETED', 'REFUNDED'), amount, 0))
       FROM gold_db.transactions.fact_transactions)
      - (SELECT SUM(refund_amount)
           FROM gold_db.transactions.fact_refunds)       AS manual_value;

-- Expected: both columns identical to the cent. A mismatch means the metric
-- expression and the reviewer's understanding of it have diverged, and the
-- view should not be granted to consumers until they agree.


-- -----------------------------------------------------------------------------
-- 3.1d Overriding the variable for one execution
-- -----------------------------------------------------------------------------
-- Finance considers 500 high-value; risk investigates from 2,000. VARIABLES
-- reassigns the declared default for this execution only. The two queries
-- below are identical except for the VARIABLES line. Run the default first.
-- -----------------------------------------------------------------------------

-- Default run: the declared threshold of 500 applies.
SELECT *
FROM SEMANTIC_VIEW(
    gold_db.semantic.techflow_revenue
    METRICS high_value_revenue, high_value_revenue_share
    DIMENSIONS transaction_month
)
ORDER BY transaction_month;

-- Expected: one row per month, with a substantial high-value share because
-- large completed payments contribute disproportionately to revenue.

-- Override run: the same query with the threshold raised to 2,000. The
-- VARIABLES clause sits after WHERE when there is one; the docs accept both
-- = and => between the variable name and the value.
SELECT *
FROM SEMANTIC_VIEW(
    gold_db.semantic.techflow_revenue
    METRICS high_value_revenue, high_value_revenue_share
    DIMENSIONS transaction_month
    VARIABLES high_value_threshold => 2000
)
ORDER BY transaction_month;

-- Expected: the same months, with smaller shares and high_value_revenue.
-- The book account returned shares of about 8-29% at 2,000 versus 33-51%
-- at 500 on 2026-09-07. Rare large payments can supply substantial revenue.
-- Nothing in the definition changed between the two runs.


-- -----------------------------------------------------------------------------
-- 3.2 The same question in direct SQL
-- -----------------------------------------------------------------------------
-- Direct querying reached general availability in March 2026. Metrics are
-- wrapped in AGG, dimensions appear in the select list and GROUP BY, and
-- Snowflake rewrites the statement into the equivalent SEMANTIC_VIEW call.
-- It exists for compatibility: a BI tool that generates standard SQL can point
-- at the view without knowing the SEMANTIC_VIEW clause exists.
-- -----------------------------------------------------------------------------

SELECT
    transaction_month,
    AGG(total_revenue)      AS total_revenue,
    AGG(transaction_count)  AS transaction_count
FROM gold_db.semantic.techflow_revenue
WHERE transaction_month >= '2025-02-01'
GROUP BY transaction_month
ORDER BY transaction_month;

-- Expected: results match query 3.1a row for row. Confirm by running both.
-- The WHERE clause is what makes that true: 3.1a filters the same way, and
-- without it this query also returns January 2025 and comes back one row longer.
--
-- Direct querying carries restrictions as of September 2026: no joins to other
-- tables, no correlated subqueries, and no PIVOT, UNPIVOT, MATCH_RECOGNIZE, LATERAL,
-- QUALIFY, or window function calls over the view. When a query needs any of
-- those, wrap it in a common table expression and apply the extra logic
-- outside. Three rules apply to both styles: an unqualified element name
-- resolves only when nothing else in the view shares it, and a request mixing
-- facts with dimensions requires all of them, including any in the WHERE
-- clause, to come from one logical table. Request metrics or facts, not both.


-- =============================================================================
-- 3.3 Creating the one-tool revenue agent
-- -----------------------------------------------------------------------------
-- The revenue key under tool_resources matches tool_spec.name. The semantic
-- view supplies the definitions; BOOK_WH executes the SQL. auto lets Snowflake
-- select the orchestration model. Reapply consumer USAGE grants after replacing
-- an existing agent. This statement does not grant access to other roles.
-- =============================================================================

CREATE OR REPLACE AGENT gold_db.semantic.techflow_revenue_agent
  COMMENT = 'Answers revenue questions from techflow_revenue'
  FROM SPECIFICATION
$$
models:
  orchestration: auto
instructions:
  orchestration: "Use SEMANTIC_VIEW; preserve category labels."
  response: "Answer with figures and state the months covered."
tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "revenue"
      description: "Metrics from the TechFlow revenue semantic view"
tool_resources:
  revenue:
    semantic_view: "gold_db.semantic.techflow_revenue"
    execution_environment:
      type: warehouse
      warehouse: BOOK_WH
$$;

-- Expected: successful creation of TECHFLOW_REVENUE_AGENT. Record the actual
-- message during the live run; the checks below state expectations, not results.

-- =============================================================================
-- AGENT CONSUMER GRANTS (Table 12.2) - template, commented for human review
-- -----------------------------------------------------------------------------
-- Substitute an existing non-owner role and a test user. Grant object access
-- as SYSADMIN/the object owner; grant the SNOWFLAKE database role as
-- ACCOUNTADMIN. Use USERADMIN/the user owner to assign the role and defaults.
-- Do not grant CREATE AGENT or OWNERSHIP to the consumer.
-- =============================================================================
-- USE ROLE SYSADMIN;
-- GRANT USAGE ON DATABASE gold_db TO ROLE <REPLACE: your agent role>;
-- GRANT USAGE ON SCHEMA gold_db.semantic TO ROLE <REPLACE: your agent role>;
-- GRANT USAGE ON SCHEMA gold_db.transactions TO ROLE <REPLACE: your agent role>;
-- GRANT USAGE ON SCHEMA gold_db.customers TO ROLE <REPLACE: your agent role>;
-- GRANT USAGE ON SCHEMA gold_db.merchants TO ROLE <REPLACE: your agent role>;
-- GRANT USAGE ON AGENT gold_db.semantic.techflow_revenue_agent
--     TO ROLE <REPLACE: your agent role>;
-- GRANT SELECT ON SEMANTIC VIEW gold_db.semantic.techflow_revenue
--     TO ROLE <REPLACE: your agent role>;
-- GRANT SELECT ON TABLE gold_db.transactions.fact_transactions
--     TO ROLE <REPLACE: your agent role>;
-- GRANT SELECT ON TABLE gold_db.transactions.fact_refunds
--     TO ROLE <REPLACE: your agent role>;
-- GRANT SELECT ON VIEW gold_db.customers.dim_customers_current
--     TO ROLE <REPLACE: your agent role>;
-- GRANT SELECT ON TABLE gold_db.merchants.dim_merchants
--     TO ROLE <REPLACE: your agent role>;
-- GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE <REPLACE: your agent role>;
-- USE ROLE ACCOUNTADMIN;
-- GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE <REPLACE: your agent role>;
-- USE ROLE USERADMIN;
-- GRANT ROLE <REPLACE: your agent role> TO USER <REPLACE: your test user>;
-- ALTER USER <REPLACE: your test user>
--     SET DEFAULT_ROLE = <REPLACE: your agent role> DEFAULT_WAREHOUSE = BOOK_WH;
-- USE ROLE SYSADMIN;
--
-- Record and restore the test user's previous defaults after verification.
-- REFERENCES is for inspecting/exporting definitions, not part of this query
-- consumer row. A reviewer who needs agent logs/traces also needs MONITOR ON
-- AGENT; keep that separate from the minimum consumer-grant test.

-- =============================================================================
-- AGENT PREVIEW WALKTHROUGH (section 3.3) - UI actions, no SQL to execute
-- -----------------------------------------------------------------------------
--   1. Run the CREATE AGENT statement above and confirm successful creation.
--   2. Open AI & ML > Agents (newer Snowsight builds label it Agent Studio)
--      > TECHFLOW_REVENUE_AGENT. On the Preview tab, start a new thread and
--      ask: What was total revenue by month?
--      On a self-service trial account the question fails with an AI-features
--      error until a credit card is on file (Admin > Billing). Adding the
--      card does not upgrade the account; see the chapter's requirements.
--   3. Expand the trace and inspect the SQL execution (system_execute_sql).
--      Expect SEMANTIC_VIEW with total_revenue by transaction_month, without
--      physical joins or repeated status logic. Read the SQL before accepting
--      the answer. Capture Figure 12.2 with the trace expanded, at least
--      1600 px wide, account identifiers out of frame.
--   4. Compare monthly figures with query 3.1a, aligning date bounds first.
--      Expected: figures match to the cent for the same months.
--
-- Then ask, in fresh conversations so earlier questions do not set the bounds:
--   Which merchant categories generated the most revenue this year?
-- Expect total_revenue by merchant_category through SEMANTIC_VIEW, with a
-- current-year bound. If the fixture has aged out, specify 2026 to see rows.
--   What is the average time to resolve a dispute?
-- The view has no dispute lifecycle fields. Record the response and any SQL;
-- do not assume a fixed refusal or fallback. Treat unsupported answers or SQL
-- outside the view as a coverage gap, not as a validated business answer.
--
-- Repeat the monthly question as a non-owner using only AGENT CONSUMER GRANTS,
-- with that role as the test user's default and BOOK_WH as default warehouse.
-- Confirm it can query the view and record any missing grant before printing.
-- Run chapter12_4_agent_backing.sql next.
-- =============================================================================
