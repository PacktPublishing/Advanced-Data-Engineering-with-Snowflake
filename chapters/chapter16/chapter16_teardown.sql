-- Chapter 16: core lab teardown. Review each statement and STOP ON ERROR.
-- Prerequisites: core setup exists; no optional failover groups or locked backups.
-- Validation: live tested on Snowflake 10.33.101, 2026-09-21; cleanup verified.
-- Placeholders use <REPLACE: description>; none required here.
-- Role: SYSADMIN inherits the lab object owner; ACCOUNTADMIN removes the monitor.
-- Save any incident evidence first. This script deletes the disposable lab database.
-- STOP if optional recovery operations were applied. Follow README cleanup first.

USE ROLE ACCOUNTADMIN;
SHOW FAILOVER GROUPS LIKE 'DR_FG';
SHOW BACKUP SETS IN SCHEMA OPS_DB.MONITORING;
-- Inspect these results BEFORE proceeding. A failover group or locked set blocks
-- this teardown path. This read-only inspection is intentionally a separate phase.

-- CORE CLEANUP: execute only after the preceding inspection.
USE ROLE SYSADMIN;
DROP STREAMLIT IF EXISTS OPS_DB.MONITORING.OPERATIONS_DASHBOARD;
DROP ALERT IF EXISTS OPS_DB.MONITORING.SETTLEMENT_STALE;
DROP BACKUP SET IF EXISTS OPS_DB.MONITORING.LEDGER_BACKUPS;
DROP DATABASE OPS_DB;
DROP WAREHOUSE OPS_WH;

USE ROLE ACCOUNTADMIN;
DROP RESOURCE MONITOR IF EXISTS DAILY_RM;
USE ROLE USERADMIN;
DROP ROLE OPS_ENGINEER;

USE ROLE SYSADMIN;
SHOW DATABASES LIKE 'OPS_DB';
SHOW WAREHOUSES LIKE 'OPS_WH';
-- Expected: neither core database nor warehouse remains visible.
