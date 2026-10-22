-- Chapter 17: get the private listing in the consumer account
-- Relationship: separate stage; run in the CONSUMER account after the provider publishes MERCHANT_PARTNER_LISTING.
-- Validation: executed in Snowflake on 2026-10-07 against a consumer in another organization.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


USE ROLE ACCOUNTADMIN;
SHOW AVAILABLE LISTINGS IS_SHARED_WITH_ME = TRUE;
-- The consumer sees no listing name. Copy the global_name of the row whose title is
-- Merchant 101 daily settlement, V1 into the placeholder.
-- OFFLINE terms need no Snowsight acceptance, so the database can be created here.

-- The role is repeated so this block runs on its own.
USE ROLE ACCOUNTADMIN;
CREATE DATABASE PARTNER_LISTING_DB FROM LISTING
  '<REPLACE: listing_global_name>';
GRANT IMPORTED PRIVILEGES ON DATABASE PARTNER_LISTING_DB
  TO ROLE SHARE_READER;
USE ROLE SHARE_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CONSUMER_WH;
SELECT currency, COUNT(*) AS row_count,
       SUM(net_settled_amount) AS total_amount
FROM PARTNER_LISTING_DB.PRODUCT.MERCHANT_DAILY_V1
GROUP BY currency;
-- Expected: one USD row, ROW_COUNT 2, TOTAL_AMOUNT 250.00.
