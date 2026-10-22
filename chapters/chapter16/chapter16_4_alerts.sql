-- Chapter 16: Implementing alerting. Independent after chapter16_0_setup.sql.
-- Execute the named blocks in order and STOP ON ERROR.
-- Prerequisites: setup role, warehouse, database, and fixture tables.
-- Validation: live tested on Snowflake 10.33.101, 2026-09-21; see README.
-- Reader-specific substitutions use <REPLACE: description>.
-- Role: OPS_ENGINEER for lab work; explicit administrator blocks only where needed.

USE ROLE OPS_ENGINEER;
USE WAREHOUSE OPS_WH;
ALTER SESSION SET TIMEZONE = 'UTC';

-- CONDITION AND ALERT DEFINITIONS: run once.
USE ROLE OPS_ENGINEER;
USE WAREHOUSE OPS_WH;
CREATE VIEW OPS_DB.MONITORING.STALE_PIPELINES AS
SELECT 'settlement' AS pipeline_name,
       MAX(last_success_at) AS last_success_at,
       COALESCE(TO_VARCHAR(MAX(last_success_at),
         'YYYY-MM-DD HH24:MI:SS.FF9'), 'missing') AS incident_key
FROM OPS_DB.MONITORING.PIPELINE_HEALTH
WHERE pipeline_name = 'settlement'
HAVING MAX(last_success_at) IS NULL
    OR MAX(last_success_at) < DATEADD(minute, -15, SYSDATE());

CREATE ALERT OPS_DB.MONITORING.SETTLEMENT_STALE
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (SELECT 1 FROM OPS_DB.MONITORING.STALE_PIPELINES))
  THEN MERGE INTO OPS_DB.MONITORING.INCIDENT_LOG t
  USING OPS_DB.MONITORING.STALE_PIPELINES s
    ON t.pipeline_name = s.pipeline_name
   AND t.incident_key = s.incident_key
  WHEN MATCHED THEN UPDATE SET last_seen_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT
    (pipeline_name, incident_key, first_seen_at, last_seen_at)
  VALUES
    (s.pipeline_name, s.incident_key,
     CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

-- VERIFY HEALTHY BRANCH: reset a fixture that became stale while reading.
UPDATE OPS_DB.MONITORING.PIPELINE_HEALTH
SET last_success_at = SYSDATE() WHERE pipeline_name = 'settlement';
SELECT * FROM OPS_DB.MONITORING.STALE_PIPELINES;
-- Expected: zero rows.

-- FAILURE INJECTION: read only after the asynchronous action finishes.
UPDATE OPS_DB.MONITORING.PIPELINE_HEALTH
SET last_success_at = DATEADD(minute, -20, SYSDATE())
WHERE pipeline_name = 'settlement';
EXECUTE ALERT OPS_DB.MONITORING.SETTLEMENT_STALE;
SELECT * FROM OPS_DB.MONITORING.INCIDENT_LOG
ORDER BY first_seen_at DESC;

-- VERIFY DEDUPLICATION: leave the heartbeat unchanged.
-- Run the next statement after the prior execution finishes, then re-query.
EXECUTE ALERT OPS_DB.MONITORING.SETTLEMENT_STALE;
SELECT pipeline_name, incident_key, COUNT(*) AS rows_per_incident
FROM OPS_DB.MONITORING.INCIDENT_LOG
GROUP BY pipeline_name, incident_key;
-- Expected: one row per key. The alert serializes its executions.

-- RECOVERY: wait for false-condition history before completing the exercise.
UPDATE OPS_DB.MONITORING.PIPELINE_HEALTH
SET last_success_at = SYSDATE()
WHERE pipeline_name = 'settlement';
SELECT * FROM OPS_DB.MONITORING.STALE_PIPELINES;
EXECUTE ALERT OPS_DB.MONITORING.SETTLEMENT_STALE;
SELECT name, state, scheduled_time, sql_error_message
FROM TABLE(OPS_DB.INFORMATION_SCHEMA.ALERT_HISTORY(
  SCHEDULED_TIME_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP()),
  ALERT_NAME => 'SETTLEMENT_STALE'))
WHERE name = 'SETTLEMENT_STALE'
ORDER BY scheduled_time DESC;

-- OPTIONAL SCHEDULE: not enabled by this script. Fixtures otherwise become stale.
-- ALTER ALERT OPS_DB.MONITORING.SETTLEMENT_STALE RESUME;
-- ALTER ALERT OPS_DB.MONITORING.SETTLEMENT_STALE SUSPEND;
