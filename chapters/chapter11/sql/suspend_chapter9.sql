-- =========================================================================
-- Chapter 11, Prerequisites: quiesce the Chapter 9 native scheduler
-- =========================================================================
-- REVIEW ONLY. Run this by hand before enabling any orchestrator in this
-- chapter so only one scheduler writes the silver and gold tables at a time.
-- Snowflake will not let you alter a graph while its root is started, so
-- suspend the root first, then children. Independent stream tasks are
-- separate graphs and suspend on their own.
-- Task names match the live Chapter 9 objects in ops_db.pipelines.
-- =========================================================================

USE ROLE ACCOUNTADMIN;

-- Independent stream-driven writer (its own graph).
ALTER TASK IF EXISTS ops_db.pipelines.process_new_transactions SUSPEND;

-- Root of the cron graph first; children cannot be altered while it is started.
ALTER TASK IF EXISTS ops_db.pipelines.load_transactions_clean SUSPEND;
ALTER TASK IF EXISTS ops_db.pipelines.build_daily_revenue SUSPEND;
ALTER TASK IF EXISTS ops_db.pipelines.pipeline_finalizer SUSPEND;

-- Serverless variant (already suspended in some accounts; keep it that way).
ALTER TASK IF EXISTS ops_db.pipelines.load_transactions_clean_flex SUSPEND;

-- Confirm nothing is left resumed before starting an external orchestrator.
SHOW TASKS IN SCHEMA ops_db.pipelines;
