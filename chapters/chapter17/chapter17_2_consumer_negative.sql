-- Chapter 17: consumer isolation checks
-- Relationship: separate stage; See README execution order; run only the stage being followed.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


USE ROLE SHARE_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CONSUMER_WH;
-- Run this permitted query. Expected: 0 rows.
SELECT merchant_id FROM PARTNER_DB.PRODUCT.MERCHANT_DAILY_V1
WHERE merchant_id = 202;
-- Execute each expected-failure statement separately, never with Run All.
-- SELECT operational_note FROM PARTNER_DB.PRODUCT.MERCHANT_DAILY_V1;
-- SELECT * FROM PARTNER_DB.PRIVATE.MERCHANT_DAILY;
