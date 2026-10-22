-- =========================================================================
-- chapter9_teardown.sql
-- Suspend and drop every task, stream, and Dynamic Table created by
-- Chapter 9 scripts. Run this when you finish the exercises.
--
-- IMPORTANT: Active serverless tasks and Dynamic Tables consume credits
-- continuously. Do not skip this step.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- =====================================================================
-- 1. Suspend all tasks. Root must be suspended FIRST — Snowflake will
--    not let you alter dependents while the root is running.
-- =====================================================================
ALTER TASK IF EXISTS ops_db.pipelines.load_transactions_clean SUSPEND;
ALTER TASK IF EXISTS ops_db.pipelines.load_transactions_clean_flex SUSPEND;
ALTER TASK IF EXISTS ops_db.pipelines.process_new_transactions SUSPEND;
ALTER TASK IF EXISTS ops_db.pipelines.pipeline_finalizer SUSPEND;
ALTER TASK IF EXISTS ops_db.pipelines.build_daily_revenue SUSPEND;

-- =====================================================================
-- 2. Drop tasks (children and finalizer first, then root)
-- =====================================================================
DROP TASK IF EXISTS ops_db.pipelines.process_new_transactions;
DROP TASK IF EXISTS ops_db.pipelines.pipeline_finalizer;
DROP TASK IF EXISTS ops_db.pipelines.build_daily_revenue;
DROP TASK IF EXISTS ops_db.pipelines.load_transactions_clean;
DROP TASK IF EXISTS ops_db.pipelines.load_transactions_clean_flex;

-- =====================================================================
-- 3. Drop streams
-- =====================================================================
DROP STREAM IF EXISTS raw_db.streaming.new_txn_stream;

-- =====================================================================
-- 4. Drop Dynamic Tables
-- =====================================================================
DROP DYNAMIC TABLE IF EXISTS gold_db.transactions.merchant_daily_revenue_dt;
DROP DYNAMIC TABLE IF EXISTS silver_db.transactions.transactions_clean_dt;

-- =====================================================================
-- 5. Verify nothing is left running
-- =====================================================================
-- All tasks live in ops_db.pipelines: a task graph must share one schema.
SHOW TASKS IN SCHEMA ops_db.pipelines;
SHOW DYNAMIC TABLES IN SCHEMA silver_db.transactions;
SHOW DYNAMIC TABLES IN SCHEMA gold_db.transactions;
SHOW STREAMS IN SCHEMA raw_db.streaming;
