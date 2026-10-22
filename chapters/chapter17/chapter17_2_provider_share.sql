-- Chapter 17: create and inspect share
-- Relationship: separate stage; Run product creation first; no account is added by this file.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.

USE ROLE SYSADMIN;
CREATE SHARE MERCHANT_SHARE;
GRANT USAGE ON DATABASE PRODUCT_DB
  TO SHARE MERCHANT_SHARE;
GRANT USAGE ON SCHEMA PRODUCT_DB.PRODUCT
  TO SHARE MERCHANT_SHARE;
GRANT REFERENCE_USAGE ON DATABASE SOURCE_DB
  TO SHARE MERCHANT_SHARE;
GRANT SELECT ON VIEW
  PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1
  TO SHARE MERCHANT_SHARE;

SHOW GRANTS TO SHARE MERCHANT_SHARE;
