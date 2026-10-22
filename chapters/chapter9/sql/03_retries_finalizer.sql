-- =========================================================================
-- Chapter 9, Section 1.3: Adding retries, failure handling, and a finalizer
-- =========================================================================
-- Configures automatic retries and a failure threshold on the root task,
-- adds a finalizer that logs each graph run to ops_db.pipelines.pipeline_run_log,
-- and creates the Serverless Tasks Flex variant of the cleansing task.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- Suspend before altering
ALTER TASK ops_db.pipelines.load_transactions_clean SUSPEND;

-- 1.3a  Retry twice, suspend after three consecutive failures
ALTER TASK ops_db.pipelines.load_transactions_clean SET
    TASK_AUTO_RETRY_ATTEMPTS = 2
    SUSPEND_TASK_AFTER_NUM_FAILURES = 3;

-- 1.3b  Finalizer: logs every graph run regardless of outcome
CREATE OR REPLACE TASK ops_db.pipelines.pipeline_finalizer
    WAREHOUSE = BOOK_WH
    FINALIZE = ops_db.pipelines.load_transactions_clean
    AS
    INSERT INTO ops_db.pipelines.pipeline_run_log
    SELECT
        CURRENT_TIMESTAMP()                                  AS logged_at,
        'transaction_transform'                              AS graph_name,
        (SELECT COUNT(*) FROM TABLE(ops_db.information_schema.task_history(
            scheduled_time_range_start => DATEADD('hour', -2, CURRENT_TIMESTAMP()))
         ) WHERE state = 'FAILED')                           AS failed_task_count;

-- Resume the graph again
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ops_db.pipelines.load_transactions_clean');

-- 1.3c  Serverless Tasks Flex variant (may be edition/region-gated)
CREATE OR REPLACE TASK ops_db.pipelines.load_transactions_clean_flex
    SCHEDULE = 'USING CRON 0 2 * * * America/New_York'
    TARGET_COMPLETION_INTERVAL = '120 MINUTE'
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    AS
    CALL ops_db.pipelines.run_cleanse();
