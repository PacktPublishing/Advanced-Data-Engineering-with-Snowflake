-- =============================================================================
-- Chapter 12: Semantic Layer and Semantic Views - Sections 2.3, 2.4, 2.5
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 2.3 Creating the Semantic View, 2.4 Extending the View with Distinct
-- Counts, Window Metrics, and Variables, 2.5 Inspecting and Validating the
-- View. Run top to bottom: stage 1, its validation set, stage 2, its
-- validation set, then the inspection commands.
--
-- Prerequisites: chapter12_0_setup.sql has run and its final query returned
-- zero in every column. The semantic view declares primary keys as assertions
-- that Snowflake does not enforce, so a fixture that fails those checks
-- produces a view that reports wrong joins without erroring.
--
-- Role convention: SYSADMIN, or any role with CREATE SEMANTIC VIEW on
-- gold_db.semantic, SELECT on the four source objects, and USAGE on BOOK_WH.
--
-- Deployment verbs: stage 1 uses CREATE OR REPLACE because it creates the
-- object and no consumer has been granted anything yet. Every statement after
-- it uses CREATE OR ALTER, which converges the object to the statement
-- submitted while preserving privileges already granted on it, with no
-- COPY GRANTS clause. Both verbs converge, so an element left out of either
-- one is removed from the view - each stage below therefore repeats the whole
-- definition rather than only its additions.
--
-- Clause order is enforced by Snowflake: TABLES, RELATIONSHIPS, VARIABLES,
-- FACTS, DIMENSIONS, METRICS, COMMENT, AI_SQL_GENERATION,
-- AI_VERIFIED_QUERIES, COPY GRANTS.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- =============================================================================
-- STAGE 1 (section 2.3): four facts (one private), five dimensions, three metrics
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW gold_db.semantic.techflow_revenue
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
      COMMENT = 'Origin of the payment: mobile, web, POS, or API',
    transactions.status AS status
      COMMENT = 'Payment lifecycle state',
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
      COMMENT = 'Mean completed payment amount, USD'
  )
  COMMENT = 'TechFlow payments semantic model, revenue owned by finance';

-- Expected: Semantic view TECHFLOW_REVENUE successfully created.


-- -----------------------------------------------------------------------------
-- Validation set for stage 1
-- -----------------------------------------------------------------------------
-- Each metric on one side, an independently written aggregation on the other.
-- Write the manual side from the business definition, not by copying the DDL,
-- or the comparison proves nothing. Every row must return PASS before you move
-- on. Running the matching set at each stage is what makes a failure point at
-- the change that caused it.
-- -----------------------------------------------------------------------------

WITH metric AS (
    SELECT total_revenue, transaction_count, average_transaction_value
      FROM SEMANTIC_VIEW(gold_db.semantic.techflow_revenue
                         METRICS total_revenue,
                                 transaction_count,
                                 average_transaction_value)
),
manual AS (
    SELECT
        (SELECT SUM(IFF(status IN ('COMPLETED', 'REFUNDED'), amount, 0))
           FROM gold_db.transactions.fact_transactions)
      - (SELECT SUM(refund_amount)
           FROM gold_db.transactions.fact_refunds)             AS total_revenue,
        (SELECT COUNT(*)
           FROM gold_db.transactions.fact_transactions)         AS transaction_count,
        (SELECT AVG(amount)
           FROM gold_db.transactions.fact_transactions
          WHERE status = 'COMPLETED')                           AS average_transaction_value
)
SELECT 'total_revenue' AS metric_name,
       ROUND(metric.total_revenue, 2)  AS metric_value,
       ROUND(manual.total_revenue, 2)  AS manual_value,
       IFF(ROUND(metric.total_revenue, 2) = ROUND(manual.total_revenue, 2),
           'PASS', 'FAIL')             AS result
  FROM metric, manual
UNION ALL
SELECT 'transaction_count',
       metric.transaction_count, manual.transaction_count,
       IFF(metric.transaction_count = manual.transaction_count, 'PASS', 'FAIL')
  FROM metric, manual
UNION ALL
SELECT 'average_transaction_value',
       ROUND(metric.average_transaction_value, 2),
       ROUND(manual.average_transaction_value, 2),
       IFF(ROUND(metric.average_transaction_value, 2)
           = ROUND(manual.average_transaction_value, 2), 'PASS', 'FAIL')
  FROM metric, manual;

-- Expected: 3 rows, all PASS.


-- =============================================================================
-- STAGE 2 (section 2.4): add the variable and four more metrics
-- -----------------------------------------------------------------------------
-- CREATE OR ALTER from here on. The whole definition is repeated because the
-- verb converges the object to what is written: anything omitted disappears.
--
-- Note on the variable's COMMENT: the documented variableDef grammar omits
-- the equals sign ([ COMMENT '<description>' ]), but Snowflake 10.28.101
-- rejects the bare form with a syntax error on the string literal. Use
-- COMMENT = '...' here, matching every other COMMENT in the view.
-- VARIABLE_COMMENT_TAKES_EQUALS in chapter12_static_checks.py is True.
-- =============================================================================

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
      COMMENT = 'Origin of the payment: mobile, web, POS, or API',
    transactions.status AS status
      COMMENT = 'Payment lifecycle state',
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
  COMMENT = 'TechFlow payments semantic model, revenue owned by finance';

-- Expected: Statement executed successfully. CREATE OR ALTER reports this
-- rather than naming the object. The view now carries seven metrics and one
-- variable.


-- -----------------------------------------------------------------------------
-- Validation set for stage 2
-- -----------------------------------------------------------------------------
-- The three stage-1 contracts still have to hold, plus one per new metric.
-- revenue_running_total is checked separately below because a window metric
-- requires every dimension named in its PARTITION BY, PARTITION BY EXCLUDING,
-- and ORDER BY clauses to appear in the request.
-- -----------------------------------------------------------------------------

WITH metric AS (
    SELECT total_revenue, transaction_count, average_transaction_value,
           customer_count, high_value_revenue, high_value_revenue_share
      FROM SEMANTIC_VIEW(gold_db.semantic.techflow_revenue
                         METRICS total_revenue,
                                 transaction_count,
                                 average_transaction_value,
                                 customer_count,
                                 high_value_revenue,
                                 high_value_revenue_share)
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
          WHERE status = 'COMPLETED')                            AS high_value_revenue_share
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
  FROM metric, manual;

-- Expected: 6 rows, all PASS.


-- -----------------------------------------------------------------------------
-- Window metric contract: the running total must equal the manual cumulative
-- -----------------------------------------------------------------------------
-- PARTITION BY EXCLUDING partitions by every dimension the query requests
-- except the ones named, so a request grouped by month alone returns a single
-- cumulative series.
-- -----------------------------------------------------------------------------

WITH metric AS (
    SELECT transaction_month, revenue_running_total
      FROM SEMANTIC_VIEW(gold_db.semantic.techflow_revenue
                         METRICS revenue_running_total
                         DIMENSIONS transaction_month)
),
monthly AS (
    SELECT DATE_TRUNC('month', f.transaction_ts)                AS transaction_month,
           SUM(IFF(f.status IN ('COMPLETED','REFUNDED'), f.amount, 0))
             - ZEROIFNULL(SUM(r.refunded))                      AS net_revenue
      FROM gold_db.transactions.fact_transactions f
      LEFT JOIN (SELECT transaction_id, SUM(refund_amount) AS refunded
                   FROM gold_db.transactions.fact_refunds
                  GROUP BY transaction_id) r
        ON r.transaction_id = f.transaction_id
     GROUP BY 1
),
manual AS (
    SELECT transaction_month,
           SUM(net_revenue) OVER (ORDER BY transaction_month
                                  ROWS BETWEEN UNBOUNDED PRECEDING
                                           AND CURRENT ROW)     AS running_total
      FROM monthly
)
SELECT COUNT(*)                                                 AS months_compared,
       SUM(IFF(ROUND(metric.revenue_running_total, 2)
               = ROUND(manual.running_total, 2), 0, 1))         AS mismatches,
       IFF(SUM(IFF(ROUND(metric.revenue_running_total, 2)
                   = ROUND(manual.running_total, 2), 0, 1)) = 0,
           'PASS', 'FAIL')                                      AS result
  FROM metric
  JOIN manual USING (transaction_month);

-- Expected: mismatches = 0, result = PASS.


-- =============================================================================
-- SECTION 2.5: inspect what you created
-- =============================================================================
-- SHOW SEMANTIC DIMENSIONS and SHOW SEMANTIC METRICS are how a consumer
-- discovers what to ask for without opening the definition. DESCRIBE returns
-- one row per property rather than per element: filter on object_kind and
-- object_name, read each property from the property and property_value pair,
-- and use parent_entity to tie elements back to their logical table. GET_DDL
-- requires REFERENCES or OWNERSHIP, and grants are not part of its output.
-- =============================================================================

SHOW SEMANTIC VIEWS IN SCHEMA gold_db.semantic;
DESCRIBE SEMANTIC VIEW gold_db.semantic.techflow_revenue;
SHOW SEMANTIC DIMENSIONS IN gold_db.semantic.techflow_revenue;
SHOW SEMANTIC METRICS IN gold_db.semantic.techflow_revenue;
SELECT GET_DDL('SEMANTIC_VIEW',
               'gold_db.semantic.techflow_revenue');

-- Expected: one row for the view, five for the dimensions, seven for the
-- metrics, and a recreatable definition from GET_DDL. Snowflake may normalize
-- the emitted text, so diff GET_DDL output against itself rather than against
-- this hand-formatted file.
-- Run chapter12_3_query_view.sql next.
