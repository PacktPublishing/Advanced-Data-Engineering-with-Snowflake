-- Chapter 16: Building observability. Independent after chapter16_0_setup.sql.
-- Execute the named blocks in order and STOP ON ERROR.
-- Prerequisites: setup role, warehouse, database, and fixture tables.
-- Validation: live tested on Snowflake 10.33.101, 2026-09-21; see README.
-- Reader-specific substitutions use <REPLACE: description>.
-- Role: OPS_ENGINEER for lab work; explicit administrator blocks only where needed.

USE ROLE OPS_ENGINEER;
USE WAREHOUSE OPS_WH;
ALTER SESSION SET TIMEZONE = 'UTC';
CREATE VIEW OPS_DB.MONITORING.DAILY_COMPUTE AS
SELECT TO_DATE(CONVERT_TIMEZONE('UTC', start_time)) AS usage_day,
       warehouse_name,
       SUM(credits_used_compute) AS compute_credits,
       CASE WHEN COUNT(credits_attributed_compute_queries)
                   = COUNT(*)
         THEN SUM(credits_attributed_compute_queries)
       END AS query_credits,
       CASE WHEN COUNT(credits_attributed_compute_queries)
                   = COUNT(*)
         THEN SUM(credits_used_compute)
            - SUM(credits_attributed_compute_queries)
       END AS idle_credits
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD(day, -8, CURRENT_DATE())
  AND start_time < DATEADD(day, -1, CURRENT_DATE())
GROUP BY usage_day, warehouse_name;

CREATE VIEW OPS_DB.MONITORING.QUERY_HEALTH AS
SELECT warehouse_name, query_parameterized_hash,
       COUNT(*) AS executions,
       PERCENTILE_CONT(0.95) WITHIN GROUP
         (ORDER BY total_elapsed_time) / 1000 AS p95_seconds,
       AVG(queued_overload_time) / 1000 AS avg_queue_seconds,
       SUM(bytes_spilled_to_remote_storage) AS remote_spill_bytes
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD(day, -8, CURRENT_DATE())
  AND start_time < DATEADD(day, -1, CURRENT_DATE())
  AND execution_status = 'SUCCESS'
  AND warehouse_name IS NOT NULL
GROUP BY warehouse_name, query_parameterized_hash;

-- VERIFY: account history can be empty in this deliberately delayed interval.
SELECT * FROM OPS_DB.MONITORING.DAILY_COMPUTE ORDER BY usage_day, warehouse_name;
SELECT * FROM OPS_DB.MONITORING.QUERY_HEALTH ORDER BY p95_seconds DESC LIMIT 20;
