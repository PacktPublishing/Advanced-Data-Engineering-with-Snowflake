-- Chapter 17: import and query shared data
-- Relationship: separate stage; Consumer setup and provider onboarding must be complete.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.

USE ROLE ACCOUNTADMIN;
CREATE DATABASE PARTNER_DB FROM SHARE
  <REPLACE: provider_qualified_share_name>;
GRANT IMPORTED PRIVILEGES ON DATABASE PARTNER_DB
  TO ROLE SHARE_READER;
USE ROLE SHARE_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CONSUMER_WH;
SELECT merchant_id, settlement_date, currency,
       net_settled_amount
FROM PARTNER_DB.PRODUCT.MERCHANT_DAILY_V1
ORDER BY settlement_date;
