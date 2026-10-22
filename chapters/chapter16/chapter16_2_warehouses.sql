-- Chapter 16: Setting suspension and spending controls. Independent after chapter16_0_setup.sql.
-- Execute the named blocks in order and STOP ON ERROR.
-- Prerequisites: setup role, warehouse, database, and fixture tables.
-- Validation: live tested on Snowflake 10.33.101, 2026-09-21. Idle-policy block
-- added 2026-09-29, rerun pending; see README.
-- Reader-specific substitutions use <REPLACE: description>.
-- Roles: SYSADMIN alters OPS_WH, which it owns; ACCOUNTADMIN creates the monitor.

-- IDLE POLICY: setup left OPS_WH at the 600-second default. SYSADMIN owns it.
USE ROLE SYSADMIN;
ALTER WAREHOUSE OPS_WH SET AUTO_SUSPEND = 60;

-- DAILY MONITOR: only ACCOUNTADMIN can create resource monitors.
USE ROLE ACCOUNTADMIN;
CREATE RESOURCE MONITOR DAILY_RM
  WITH CREDIT_QUOTA = 10
       FREQUENCY = DAILY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 70 PERCENT DO NOTIFY
           ON 90 PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE OPS_WH
  SET RESOURCE_MONITOR = DAILY_RM;

SHOW WAREHOUSES LIKE 'OPS_WH';
SELECT "name", "size", "auto_suspend", "auto_resume",
       "resource_monitor"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
SHOW RESOURCE MONITORS LIKE 'DAILY_RM';
