-- =========================================================================
-- Chapter 9, Section 1.2: Chaining tasks into a task graph
-- =========================================================================
-- Adds the aggregation task downstream of the cleansing task using AFTER,
-- then resumes the whole graph with SYSTEM$TASK_DEPENDENTS_ENABLE.
--
-- Both tasks live in ops_db.pipelines because every task in a graph must
-- share one database and schema. The aggregation writes cross-database to
-- gold_db with a fully qualified name.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- Suspend the root before adding a child
ALTER TASK ops_db.pipelines.load_transactions_clean SUSPEND;

-- 1.2  Aggregation task: daily merchant revenue from clean transactions
CREATE OR REPLACE TASK ops_db.pipelines.build_daily_revenue
    WAREHOUSE = BOOK_WH
    AFTER ops_db.pipelines.load_transactions_clean
    AS
    INSERT OVERWRITE INTO gold_db.transactions.merchant_daily_revenue
    SELECT
        merchant_id,
        DATE_TRUNC('day', transaction_ts)  AS revenue_date,
        COUNT(*)                           AS transaction_count,
        SUM(amount)                        AS gross_revenue
    FROM silver_db.transactions.transactions_clean
    WHERE status = 'COMPLETED'
    GROUP BY merchant_id, DATE_TRUNC('day', transaction_ts);

-- Resume the entire graph in one call
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ops_db.pipelines.load_transactions_clean');
