-- Chapter 19: Common setup and synthetic fixture
-- Run once before any section. Each later script is independent; run only the section you follow.
-- Prerequisites: USERADMIN and SYSADMIN; inspect the reserved lab names in the README before running.
-- Validation: documentation checked October 2026; not executed on a live Snowflake account.
-- Placeholder convention: <REPLACE: description> only for reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN only grants account privileges.
-- Stop on any error. CREATE statements deliberately fail on existing lab tables/services.

USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS BI_READER;
CREATE ROLE IF NOT EXISTS NO_DATA_READER;
GRANT ROLE BI_READER TO ROLE SYSADMIN;
GRANT ROLE NO_DATA_READER TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS ANALYTICS_DB;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_DB.SERVING;
CREATE WAREHOUSE IF NOT EXISTS BUILD_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
CREATE WAREHOUSE IF NOT EXISTS BI_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
-- XS bounds the demonstration's initial capacity, not a sizing recommendation.
-- The BI warehouse block in chapter19_1_bi.sql retunes BI_WH for dashboard traffic.
USE DATABASE ANALYTICS_DB;
USE SCHEMA SERVING;
USE WAREHOUSE BUILD_WH;
ALTER SESSION SET TIMEZONE = 'UTC';

-- Deliberately no IF NOT EXISTS here: do not append duplicate seed rows on rerun.
CREATE TABLE PAYMENT_ATTEMPTS (
  attempt_id NUMBER(10,0) NOT NULL,
  event_date DATE NOT NULL,
  merchant_id VARCHAR NOT NULL,
  amount_usd NUMBER(12,2) NOT NULL,
  approved BOOLEAN NOT NULL,
  source_updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
-- Synthetic historical event dates; source_updated_at is the lab load time.
INSERT INTO PAYMENT_ATTEMPTS
  (attempt_id, event_date, merchant_id, amount_usd, approved)
VALUES
  (1, '2026-09-01', 'M100', 100.00, TRUE),
  (2, '2026-09-01', 'M100', 50.00, TRUE),
  (3, '2026-09-01', 'M100', 25.00, TRUE),
  (4, '2026-09-01', 'M100', 40.00, FALSE),
  (5, '2026-09-01', 'M200', 200.00, TRUE),
  (6, '2026-09-01', 'M200', 60.00, FALSE),
  (7, '2026-09-02', 'M100', 120.00, TRUE),
  (8, '2026-09-02', 'M100', 80.00, TRUE),
  (9, '2026-09-02', 'M100', 50.00, FALSE),
  (10, '2026-09-02', 'M100', 25.00, FALSE),
  (11, '2026-09-02', 'M200', 100.00, TRUE),
  (12, '2026-09-02', 'M200', 100.00, FALSE);

-- Consumer visibility. Data grants come later, one object at a time, per section.
GRANT USAGE ON DATABASE ANALYTICS_DB TO ROLE BI_READER;
GRANT USAGE ON SCHEMA ANALYTICS_DB.SERVING TO ROLE BI_READER;
GRANT USAGE ON WAREHOUSE BI_WH TO ROLE BI_READER;
-- NO_DATA_READER receives object visibility for a later negative agent test only.
GRANT USAGE ON DATABASE ANALYTICS_DB TO ROLE NO_DATA_READER;
GRANT USAGE ON SCHEMA ANALYTICS_DB.SERVING TO ROLE NO_DATA_READER;
GRANT USAGE ON WAREHOUSE BI_WH TO ROLE NO_DATA_READER;

-- FIXTURE VERIFICATION: expect 12, 7, 675.00.
SELECT COUNT(*) AS attempts,
       COUNT_IF(approved) AS approved_attempts,
       SUM(IFF(approved, amount_usd, 0)) AS approved_volume_usd
FROM ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS;
-- The reporting view is created in chapter19_1_bi.sql, section 1.2.
