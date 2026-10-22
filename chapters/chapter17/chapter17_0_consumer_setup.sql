-- Chapter 17: consumer role and warehouse
-- Relationship: separate stage; Run in CONSUMER account. New lab names required; never replace existing roles.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


USE ROLE USERADMIN;
CREATE ROLE SHARE_READER;
SET lab_user = CURRENT_USER();
GRANT ROLE SHARE_READER TO USER IDENTIFIER($lab_user);
GRANT ROLE SHARE_READER TO ROLE SYSADMIN;
USE ROLE SYSADMIN;
CREATE WAREHOUSE CONSUMER_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
GRANT USAGE ON WAREHOUSE CONSUMER_WH TO ROLE SHARE_READER;
USE ROLE ACCOUNTADMIN;
SHOW SHARES;
