-- =========================================================================
-- Chapter 9, Section 4.3: Monitoring the pipeline
-- =========================================================================
-- Two monitoring queries: failed task runs in the last day, and Dynamic
-- Table refresh history for the gold layer with completion_target so you can
-- see whether each refresh is keeping up with its TARGET_LAG.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- 4.3a  Failed task runs in the last day
SELECT name, database_name, scheduled_time, state, error_message
FROM TABLE(ops_db.information_schema.task_history(
    scheduled_time_range_start => DATEADD('day', -1, CURRENT_TIMESTAMP()),
    scheduled_time_range_end => CURRENT_TIMESTAMP(),
    result_limit => 10000
))
WHERE database_name = 'OPS_DB' AND schema_name = 'PIPELINES'
  AND state = 'FAILED'
ORDER BY scheduled_time DESC;

-- 4.3b  Dynamic Table refresh history for gold
-- A positive seconds_behind_target means the refresh finished after the point
-- it needed to in order to stay within the lag.
SELECT name, refresh_action, state, refresh_end_time, completion_target,
       DATEDIFF('second', completion_target, refresh_end_time) AS seconds_behind_target
FROM TABLE(gold_db.information_schema.dynamic_table_refresh_history(
    name_prefix => 'GOLD_DB.TRANSACTIONS.',
    result_limit => 50
))
ORDER BY refresh_end_time DESC;

-- Run both queries from SQL files in Snowsight Workspaces. An empty failure
-- result only covers visible runs within the function's 10,000-row limit.
-- For optional combined charts, use Streamlit in Snowflake. This file does
-- not create an app or a background refresh schedule.
