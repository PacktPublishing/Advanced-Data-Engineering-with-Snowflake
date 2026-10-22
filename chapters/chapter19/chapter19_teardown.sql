-- Chapter 19: Optional lab teardown
-- Run after every section you followed. Pause CoWork automations first (section 5.3).
-- Prerequisites: confirm these reserved objects contain no work to retain.
-- Validation: documentation checked October 2026; not executed on a live Snowflake account.
-- Placeholder convention: <REPLACE: description> only for reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN only grants account privileges.
-- Destructive cleanup is intentionally opt-in: inspect and uncomment only objects you created.
-- No procedure in this repository executes this file automatically.

USE ROLE SYSADMIN;
-- ALTER INTERACTIVE TABLE ANALYTICS_DB.SERVING.DAILY_INTERACTIVE SUSPEND;
-- ALTER WAREHOUSE INTERACTIVE_WH SUSPEND;
-- DROP APPLICATION IF EXISTS ANALYTICS_APP;
-- DROP APPLICATION PACKAGE IF EXISTS ANALYTICS_PKG;
-- DROP WAREHOUSE IF EXISTS INTERACTIVE_WH;
-- DROP DATABASE IF EXISTS ANALYTICS_DB;  -- includes the benchmark tables, semantic view, and agent
-- DROP WAREHOUSE IF EXISTS BUILD_WH;
-- DROP WAREHOUSE IF EXISTS BI_WH;

-- Account privileges this lab granted (chapter19_3_native_app.sql, chapter19_4_agents.sql).
-- Keep them if SYSADMIN held them before the lab.
-- USE ROLE ACCOUNTADMIN;
-- REVOKE CREATE APPLICATION PACKAGE ON ACCOUNT FROM ROLE SYSADMIN;
-- REVOKE CREATE APPLICATION ON ACCOUNT FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER FROM ROLE SYSADMIN;

-- Tokens created for the chat client (section 4.4), one per tested identity.
-- ALTER USER REMOVE PROGRAMMATIC ACCESS TOKEN payment_chat;
-- ALTER USER REMOVE PROGRAMMATIC ACCESS TOKEN payment_chat_restricted;

-- USE ROLE USERADMIN;
-- DROP ROLE IF EXISTS NO_DATA_READER;
-- DROP ROLE IF EXISTS BI_READER;
-- Remove saved CoWork lab artifacts and the review-payment-performance skill in CoWork.

USE ROLE SYSADMIN;
SHOW DATABASES LIKE 'ANALYTICS_DB';
SHOW WAREHOUSES;
SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
 WHERE "name" IN ('BI_WH','INTERACTIVE_WH','BUILD_WH');
-- Expect no lab objects after the selected cleanup has completed.
