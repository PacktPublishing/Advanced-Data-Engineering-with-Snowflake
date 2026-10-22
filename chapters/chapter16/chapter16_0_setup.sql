-- Chapter 16: shared setup for cost, observability, alerts, and restore exercises.
-- Run once before the selected section. Run statement by statement and STOP ON ERROR.
-- Prerequisites: administrative access; account telemetry; Streamlit warehouse runtime.
-- Validation: live tested on Snowflake 10.33.101, 2026-09-21. OPS_WH AUTO_SUSPEND
-- line removed 2026-09-29, rerun pending; see README.
-- Reader values use <REPLACE: description>; no substitutions required in this file.
-- Roles: USERADMIN creates roles; SYSADMIN provisions; ACCOUNTADMIN grants account rights.
-- Names are dedicated to this lab. Plain CREATE refuses existing lab objects.

USE ROLE SYSADMIN;
CREATE DATABASE OPS_DB COMMENT = 'Chapter 16 disposable operations lab';
CREATE SCHEMA OPS_DB.MONITORING;
-- AUTO_SUSPEND stays at the 600-second default; chapter16_2_warehouses.sql
-- sets the lab's 60-second idle policy as a reader step.
CREATE WAREHOUSE OPS_WH
  WAREHOUSE_TYPE = 'STANDARD'
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

USE ROLE USERADMIN;
CREATE ROLE OPS_ENGINEER COMMENT = 'Chapter 16 telemetry and lab object owner';
GRANT ROLE OPS_ENGINEER TO ROLE SYSADMIN;
SET lab_user = CURRENT_USER();
GRANT ROLE OPS_ENGINEER TO USER IDENTIFIER($lab_user);

USE ROLE ACCOUNTADMIN;
-- Account privileges require this administrator role. Ordinary lab work does not.
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER TO ROLE OPS_ENGINEER;
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER TO ROLE OPS_ENGINEER;
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE OPS_ENGINEER;
GRANT EXECUTE MANAGED ALERT ON ACCOUNT TO ROLE OPS_ENGINEER;

USE ROLE SYSADMIN;
GRANT USAGE ON DATABASE OPS_DB TO ROLE OPS_ENGINEER;
GRANT USAGE ON SCHEMA OPS_DB.MONITORING TO ROLE OPS_ENGINEER;
GRANT CREATE TABLE, CREATE VIEW, CREATE ALERT, CREATE STREAMLIT,
      CREATE STAGE, CREATE BACKUP SET
  ON SCHEMA OPS_DB.MONITORING TO ROLE OPS_ENGINEER;
GRANT USAGE ON WAREHOUSE OPS_WH TO ROLE OPS_ENGINEER;

USE ROLE OPS_ENGINEER;
USE WAREHOUSE OPS_WH;
USE DATABASE OPS_DB;
USE SCHEMA MONITORING;
ALTER SESSION SET TIMEZONE = 'UTC';
ALTER SESSION SET QUERY_TAG = 'app=operations;env=lab;owner=payments';

-- A real publisher advances this watermark only after validated output commits.
CREATE TABLE PIPELINE_HEALTH (
  pipeline_name VARCHAR NOT NULL,
  last_success_at TIMESTAMP_NTZ
);
INSERT INTO PIPELINE_HEALTH VALUES ('settlement', SYSDATE());

CREATE TABLE INCIDENT_LOG (
  pipeline_name VARCHAR NOT NULL,
  incident_key VARCHAR NOT NULL,
  first_seen_at TIMESTAMP_LTZ NOT NULL,
  last_seen_at TIMESTAMP_LTZ NOT NULL
);

-- Permanent table for the backup exercise; do not convert it to TRANSIENT.
CREATE TABLE SETTLEMENT_LEDGER (
  payment_id NUMBER NOT NULL,
  batch_id VARCHAR NOT NULL,
  amount NUMBER(12,2) NOT NULL
);
INSERT INTO SETTLEMENT_LEDGER VALUES
  (1, 'batch-001', 10.00), (2, 'batch-001', 20.00), (3, 'batch-001', 30.00);

SELECT CURRENT_ACCOUNT(), CURRENT_ROLE(), CURRENT_WAREHOUSE();
SELECT COUNT(*) AS heartbeat_rows FROM PIPELINE_HEALTH;
SELECT COUNT(*) AS ledger_rows, SUM(amount) AS ledger_amount FROM SETTLEMENT_LEDGER;
-- Expected: OPS_ENGINEER / OPS_WH; 1 heartbeat; 3 ledger rows / 60.00.
