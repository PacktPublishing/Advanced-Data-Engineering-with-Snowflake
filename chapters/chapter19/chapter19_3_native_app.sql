-- Chapter 19: Native App provider preparation
-- Independent optional section after common setup; do not run every service by default.
-- Prerequisites: common setup; administrator supplies CREATE APPLICATION PACKAGE and CREATE APPLICATION
-- Validation: documentation checked October 2026; SQL blocks run live on the author's sandbox account on 2026-10-24, including the four-file upload and the Streamlit 1.35.0 pin.
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

-- Grant-based sharing through a proxy view is labelled legacy in the Native App docs; declaring
-- shared content in the manifest is the recommended path. This lab keeps the proxy view because
-- it pins the shared columns to the app version.

-- STAGE UPLOAD WALKTHROUGH (UI-only, deliberately commented):
-- In Snowsight select Ingestion > Add Data > Load files into a Stage, then ANALYTICS_DB.APP_CODE.SRC.
-- Upload native_app/manifest.yml and native_app/setup.sql with no path (stage root).
-- Upload native_app/streamlit/app.py and native_app/streamlit/environment.yml with the path streamlit.
-- Do not upload the containing native_app directory as another path component.
-- After upload, verify the four paths before running chapter19_3_install.sql.
LIST @ANALYTICS_DB.APP_CODE.SRC;
