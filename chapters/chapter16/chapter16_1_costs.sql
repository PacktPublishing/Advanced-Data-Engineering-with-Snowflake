-- Chapter 16: Analyzing financial operations. Independent after chapter16_0_setup.sql.
-- Execute the named blocks in order and STOP ON ERROR.
-- Prerequisites: setup role, warehouse, database, and fixture tables.
-- Validation: live tested on Snowflake 10.33.101, 2026-09-21. Attribution block
-- simplified 2026-09-29, rerun pending; see README.
-- Reader-specific substitutions use <REPLACE: description>.
-- Role: OPS_ENGINEER for lab work; explicit administrator blocks only where needed.

USE ROLE OPS_ENGINEER;
USE WAREHOUSE OPS_WH;
ALTER SESSION SET TIMEZONE = 'UTC';
SELECT usage_date, service_type,
       SUM(credits_billed) AS billed_credits
FROM snowflake.account_usage.metering_daily_history
WHERE usage_date >= DATEADD(day, -8, CURRENT_DATE())
  AND usage_date < DATEADD(day, -1, CURRENT_DATE())
GROUP BY usage_date, service_type
ORDER BY usage_date, billed_credits DESC;

-- QUERY_ATTRIBUTION_HISTORY carries QUERY_TAG and QUERY_PARAMETERIZED_HASH itself.
SELECT COALESCE(NULLIF(query_tag, ''), '(untagged)') AS workload,
       query_parameterized_hash,
       COUNT(*) AS attributed_executions,
       SUM(credits_attributed_compute) AS query_credits
FROM snowflake.account_usage.query_attribution_history
WHERE start_time >= DATEADD(day, -8, CURRENT_DATE())
  AND start_time < DATEADD(day, -1, CURRENT_DATE())
GROUP BY workload, query_parameterized_hash
ORDER BY query_credits DESC
LIMIT 20;

-- OPTIONAL ADAPTIVE METERING: read only; run only when the view is available.
-- Metering-hour boundary aligns charges with hourly accounting, including jobs
-- that started before the period. Aggregate rows before joining query-level data.
SELECT query_id, SUM(credits_used_compute) AS compute_credits,
       SUM(credits_used_cloud_services) AS cloud_services_credits,
       SUM(credits_used) AS metered_credits
FROM snowflake.account_usage.query_metering_history
WHERE query_metering_hour >= DATEADD(day, -8, CURRENT_DATE())
  AND query_metering_hour < DATEADD(day, -1, CURRENT_DATE())
GROUP BY query_id
ORDER BY metered_credits DESC
LIMIT 20;
