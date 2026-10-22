-- =============================================================================
-- Chapter 5 — Section 4: Optimizing Query Performance.
-- Standalone: run chapter5_0_setup.sql once first, and run
-- chapter5_1_window_functions.sql so fact_transactions exists with data.
--
-- Reference-only section: clustering and search optimization deliver
-- measurable benefit at multi-terabyte scale, and both ALTERs require
-- Enterprise Edition or higher (Trial/Standard accounts error — skip them).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;


-- =============================================================================
-- 4.1 Reading Query Profiles
-- =============================================================================

-- No SQL required. In Snowsight, open Activity > Query History, pick a
-- completed query, and click the Profile tab. Triage signals: a query that
-- scans more than about half of the table's micro-partitions (clustering may
-- help), spilling to local/remote storage (warehouse sizing), and join
-- operators emitting far more rows than they consume (join key).


-- =============================================================================
-- 4.2 Applying Clustering Keys
-- =============================================================================
--
-- All four criteria must hold (scale, selectivity, access concentration,
-- query-to-DML ratio) before clustering is worth the spend.

ALTER TABLE gold_db.transactions.fact_transactions
    CLUSTER BY (transaction_ts::DATE, merchant_id);

SELECT SYSTEM$CLUSTERING_INFORMATION(
    'gold_db.transactions.fact_transactions',
    '(transaction_ts::DATE, merchant_id)'
);

-- Monitor reclustering credit consumption against query-time savings:
--   SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
--   WHERE TABLE_NAME = 'FACT_TRANSACTIONS'
--   ORDER BY START_TIME DESC;


-- =============================================================================
-- 4.3 Enabling Search Optimization
-- =============================================================================
--
-- Search optimization applies to equality predicates here; range predicates
-- (BETWEEN, >=) should rely on clustering instead. Rule of thumb: skip search
-- optimization on tables with fewer than ~100 point-lookup queries per day.
-- On Gen2 warehouses, Snowflake Optima Indexing can create hidden indexes
-- automatically; the manual ADD below is the explicit-control path.

-- Step 1: estimate cost first (second arg narrows the estimate to the
-- planned EQUALITY(...) columns)
SELECT SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS(
    'gold_db.transactions.fact_transactions',
    'EQUALITY(transaction_id, customer_id)'
);

-- Step 2: enable on equality lookup columns (Enterprise Edition+)
ALTER TABLE gold_db.transactions.fact_transactions
    ADD SEARCH OPTIMIZATION ON EQUALITY(transaction_id, customer_id);

-- Step 3: monitor ongoing cost
--   SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.SEARCH_OPTIMIZATION_HISTORY
--   WHERE TABLE_NAME = 'FACT_TRANSACTIONS'
--   ORDER BY START_TIME DESC;
