-- Chapter 19: Native App provider preparation
-- Independent optional section after common setup; do not run every service by default.
-- Prerequisites: common setup; administrator supplies CREATE APPLICATION PACKAGE and CREATE APPLICATION
-- Validation: documentation checked October 2026; not executed on a live Snowflake account.
-- Placeholder convention: <REPLACE: description> only for reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN only grants account privileges.
-- Stop on any error. CREATE statements deliberately fail on existing lab tables/services.

-- Run account grants only when needed; do not change account security defaults.
USE ROLE ACCOUNTADMIN;
GRANT CREATE APPLICATION PACKAGE ON ACCOUNT TO ROLE SYSADMIN;
GRANT CREATE APPLICATION ON ACCOUNT TO ROLE SYSADMIN;

-- PROVIDER PREPARATION BLOCK.
USE ROLE SYSADMIN;
USE WAREHOUSE BUILD_WH;
CREATE APPLICATION PACKAGE ANALYTICS_PKG;
CREATE SCHEMA ANALYTICS_PKG.SHARED_DATA;
CREATE TABLE ANALYTICS_PKG.SHARED_DATA.DAILY_METRICS AS
SELECT event_date, merchant_id, attempts, approved_attempts, approved_amount_usd
FROM ANALYTICS_DB.SERVING.DAILY_METRICS;
GRANT USAGE ON SCHEMA ANALYTICS_PKG.SHARED_DATA
  TO SHARE IN APPLICATION PACKAGE ANALYTICS_PKG;
GRANT SELECT ON TABLE ANALYTICS_PKG.SHARED_DATA.DAILY_METRICS
  TO SHARE IN APPLICATION PACKAGE ANALYTICS_PKG;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_DB.APP_CODE;
CREATE STAGE IF NOT EXISTS ANALYTICS_DB.APP_CODE.SRC;
SELECT COUNT(*) AS rows_in_package,
       SUM(approved_amount_usd) AS approved_volume_usd
FROM ANALYTICS_PKG.SHARED_DATA.DAILY_METRICS;
-- Expect four rows and 675.00. Snapshot does not auto-refresh from the source.

-- STAGE UPLOAD WALKTHROUGH (UI-only, deliberately commented):
-- In Snowsight select the SRC stage under ANALYTICS_DB.APP_CODE.
-- Upload native_app/manifest.yml and native_app/setup.sql at stage root.
-- Upload native_app/streamlit/app.py under the stage's streamlit/ path.
-- Do not upload the containing native_app directory as another path component.
-- After upload, verify the three paths before running chapter19_3_install.sql.
LIST @ANALYTICS_DB.APP_CODE.SRC;
