-- Chapter 19: Interactive serving, benchmark data, reconciliation, load results, suspension (sections 2.2, 2.3)
-- Independent after common setup and the reporting view from chapter19_1_bi.sql.
-- Prerequisites: supported region; explicit acceptance of the one-hour minimum charge on every resume.
-- Validation: documentation checked October 2026; every block run live on the author's sandbox account on 2026-10-24,
-- including the freshness block with its UTC session line and three load runs. The commented ACCOUNT_USAGE query was run live the same day.
-- Placeholder convention: <REPLACE: description> only for reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN only grants account privileges.
-- Stop on any error. CREATE statements deliberately fail on existing lab tables/services.
-- Order: interactive table, benchmark data, warehouse (starts billing), measurement,
-- reconciliation, freshness, then three chapter19_2_load_test.py runs (load results after each),
-- and suspension in one session.

-- INTERACTIVE TABLE BLOCK.
USE ROLE SYSADMIN;
USE WAREHOUSE BUILD_WH;
CREATE INTERACTIVE TABLE
  ANALYTICS_DB.SERVING.DAILY_INTERACTIVE
  CLUSTER BY (merchant_id, event_date)
  TARGET_LAG = '1 minute'
  WAREHOUSE = BUILD_WH
AS SELECT event_date, merchant_id,
          COUNT(*) AS attempts,
          COUNT_IF(approved) AS approved_attempts,
          SUM(IFF(approved, amount_usd, 0))
            AS approved_amount_usd,
          MAX(source_updated_at) AS source_updated_at
FROM ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS
GROUP BY event_date, merchant_id;

-- BENCHMARK DATA BLOCK: standard billing on BUILD_WH, about 20 million rows.
USE ROLE SYSADMIN;
USE WAREHOUSE BUILD_WH;
CREATE TABLE ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_BENCH AS
SELECT SEQ8() AS attempt_id,
       DATEADD(day, UNIFORM(0, 179, RANDOM()),
               '2026-03-01'::DATE) AS event_date,
       'M' || LPAD(ZIPF(1, 2000, RANDOM())::VARCHAR, 4, '0')
         AS merchant_id,
       UNIFORM(5::FLOAT, 500::FLOAT, RANDOM())::NUMBER(12,2)
         AS amount_usd,
       UNIFORM(1, 100, RANDOM()) <= 85 AS approved
FROM TABLE(GENERATOR(ROWCOUNT => 20000000))
ORDER BY merchant_id, event_date;
CREATE INTERACTIVE TABLE
  ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_INTERACTIVE
  CLUSTER BY (merchant_id, event_date)
AS SELECT * FROM ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_BENCH;

-- Benchmark skew check: expect M0001, M0002, M0003 with roughly 2.4, 1.2, and 0.8 million rows.
SELECT merchant_id, COUNT(*) AS attempts
FROM ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_BENCH
GROUP BY merchant_id
ORDER BY attempts DESC
LIMIT 3;

-- WAREHOUSE BLOCK: billing starts at the explicit RESUME.
USE ROLE SYSADMIN;
CREATE INTERACTIVE WAREHOUSE INTERACTIVE_WH
  TABLES (ANALYTICS_DB.SERVING.DAILY_INTERACTIVE,
          ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_INTERACTIVE,
          ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_BENCH)
  AUTO_SUSPEND = 86400
  AUTO_RESUME = FALSE
  INITIALLY_SUSPENDED = TRUE;
ALTER WAREHOUSE INTERACTIVE_WH
  SET FALLBACK_WAREHOUSE = BI_WH;
GRANT USAGE ON WAREHOUSE INTERACTIVE_WH TO ROLE BI_READER;
GRANT SELECT ON TABLE ANALYTICS_DB.SERVING.DAILY_INTERACTIVE
  TO ROLE BI_READER;
GRANT SELECT ON TABLE ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_BENCH
  TO ROLE BI_READER;
GRANT SELECT ON TABLE ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_INTERACTIVE
  TO ROLE BI_READER;
ALTER WAREHOUSE INTERACTIVE_WH RESUME;

-- MEASUREMENT BLOCK: expect 375.00, 5, 8.
USE ROLE BI_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE INTERACTIVE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'analytics:interactive:m100';
SELECT SUM(approved_amount_usd) AS approved_volume_usd,
       SUM(approved_attempts) AS approved_attempts,
       SUM(attempts) AS attempts
FROM ANALYTICS_DB.SERVING.DAILY_INTERACTIVE
WHERE merchant_id = 'M100'
  AND event_date >= '2026-09-01'::DATE
  AND event_date < '2026-09-03'::DATE;

-- RECONCILIATION BLOCK: standard warehouse; expect zero rows in each direction.
-- Standard warehouses read interactive tables; that is how fallback execution works.
USE ROLE SYSADMIN;
USE WAREHOUSE BI_WH;
SELECT * FROM ANALYTICS_DB.SERVING.DAILY_METRICS
MINUS
SELECT * FROM ANALYTICS_DB.SERVING.DAILY_INTERACTIVE;
SELECT * FROM ANALYTICS_DB.SERVING.DAILY_INTERACTIVE
MINUS
SELECT * FROM ANALYTICS_DB.SERVING.DAILY_METRICS;
-- Inspect last_completed_refresh_state and latest_data_timestamp. SHOW needs no warehouse.
SHOW INTERACTIVE TABLES LIKE 'DAILY_INTERACTIVE'
  IN SCHEMA ANALYTICS_DB.SERVING;

-- FRESHNESS BLOCK: move one source timestamp forward without changing any total.
-- Until the next refresh, both MINUS queries above return the M200 September 2 row.
-- source_updated_at is TIMESTAMP_NTZ in UTC wall time (the setup script sets the session to UTC),
-- so this session must be UTC too, or a western time zone writes an earlier time.
USE ROLE SYSADMIN;
USE WAREHOUSE BUILD_WH;
ALTER SESSION SET TIMEZONE = 'UTC';
UPDATE ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS
  SET source_updated_at = CURRENT_TIMESTAMP()
  WHERE attempt_id = 12;
SHOW INTERACTIVE TABLES LIKE 'DAILY_INTERACTIVE'
  IN SCHEMA ANALYTICS_DB.SERVING;
-- Rerun the SHOW until latest_data_timestamp passes the update time (within about a minute),
-- then rerun the reconciliation block and expect zero rows again.

-- Run chapter19_2_load_test.py three times now (see README), the load results block after each.

-- LOAD RESULTS BLOCK: run right after each load run, as the owner of both warehouses.
-- The table function returns at most 10,000 rows (RESULT_LIMIT), keeping the most recent, and
-- applies that limit before WHERE. Eight workers send more than 10,000 measurement queries in
-- a run, so queries stops at 10,000 and the percentiles describe the latest 10,000 queries.
-- Use this block for Snowflake-side latency. For exact counts, use the ACCOUNT_USAGE query below.
USE ROLE SYSADMIN;
USE WAREHOUSE BI_WH;
SELECT query_tag, warehouse_name,
       COUNT(*) AS queries,
       COUNT_IF(execution_status <> 'SUCCESS') AS failed,
       COUNT_IF(total_elapsed_time > 5000) AS over_5s,
       MEDIAN(total_elapsed_time) AS p50_ms,
       PERCENTILE_CONT(0.95) WITHIN GROUP
         (ORDER BY total_elapsed_time) AS p95_ms
FROM TABLE(ANALYTICS_DB.INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(
       USER_NAME => '<REPLACE: test user name>',
       END_TIME_RANGE_START => DATEADD(minute, -10, CURRENT_TIMESTAMP()),
       RESULT_LIMIT => 10000))
WHERE query_tag LIKE 'analytics:load:%:measure'
GROUP BY query_tag, warehouse_name
ORDER BY query_tag, warehouse_name;
-- over_5s counts statements that ran longer than five seconds inside Snowflake, the only
-- fallback candidates: open their query IDs in Query Profile and look for fault_handling_time.
-- The client's "over 5 s" count is measured on the client and includes network and client stalls.

-- EXACT COUNTS (optional, deliberately commented): ACCOUNT_USAGE has no row limit but lags by up
-- to 45 minutes and needs a role that can read the SNOWFLAKE database. Run it after the third run.
-- USE ROLE ACCOUNTADMIN;
-- USE WAREHOUSE BI_WH;
-- SELECT query_tag, warehouse_name,
--        COUNT(*) AS queries,
--        COUNT_IF(execution_status <> 'SUCCESS') AS failed,
--        MEDIAN(total_elapsed_time) AS p50_ms,
--        PERCENTILE_CONT(0.95) WITHIN GROUP
--          (ORDER BY total_elapsed_time) AS p95_ms
-- FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
-- WHERE user_name = '<REPLACE: test user name>'
--   AND query_tag LIKE 'analytics:load:%:measure'
--   AND start_time >= DATEADD(hour, -3, CURRENT_TIMESTAMP())
-- GROUP BY query_tag, warehouse_name
-- ORDER BY query_tag, warehouse_name;

-- SUSPENSION BLOCK: run when measurement is complete, including after an error.
USE ROLE SYSADMIN;
ALTER INTERACTIVE TABLE ANALYTICS_DB.SERVING.DAILY_INTERACTIVE SUSPEND;
ALTER WAREHOUSE INTERACTIVE_WH SUSPEND;
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER SESSION UNSET QUERY_TAG;
SHOW WAREHOUSES LIKE 'INTERACTIVE_WH';
SHOW INTERACTIVE TABLES LIKE 'DAILY_INTERACTIVE'
  IN SCHEMA ANALYTICS_DB.SERVING;
-- Expect warehouse state SUSPENDED and table scheduling_state SUSPENDED.
