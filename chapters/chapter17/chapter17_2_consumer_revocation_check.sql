-- Chapter 17: confirm revocation
-- Relationship: separate stage; See README execution order; run only the stage being followed.
-- Validation: executed in Snowflake on 2026-10-07, after the 2026-10-03 revocation.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


USE ROLE SHARE_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CONSUMER_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
-- Run this expected-failure query separately AFTER the provider revokes access.
-- Expected error: Shared database is no longer available for use.
-- SELECT merchant_id, settlement_date, currency, net_settled_amount
-- FROM PARTNER_DB.PRODUCT.MERCHANT_DAILY_V1
-- ORDER BY settlement_date;
