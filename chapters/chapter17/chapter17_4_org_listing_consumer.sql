-- Chapter 17: discovery-only role and acquisition in the consumer account
-- Relationship: separate stage; run in the CONSUMER account. Part 1 before the provider publishes; part 2 after.
-- Validation: executed in Snowflake on 2026-10-05, provider and consumer in one organization.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


-- Part 1: a role that can discover the listing but is not in its access list.
USE ROLE USERADMIN;
CREATE ROLE LISTING_BROWSER;
SET lab_user = CURRENT_USER();
GRANT ROLE LISTING_BROWSER TO USER IDENTIFIER($lab_user);
GRANT ROLE LISTING_BROWSER TO ROLE SYSADMIN;
USE ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE CONSUMER_WH TO ROLE LISTING_BROWSER;

-- Part 2: run after the provider publishes MERCHANT_INTERNAL_LISTING.
USE ROLE ACCOUNTADMIN;
SHOW AVAILABLE LISTINGS IS_ORGANIZATION = TRUE;
-- The consumer sees no listing name. Copy the global_name of the row whose title is
-- Merchant 101 daily settlement, V1 into the placeholder.

-- The role is repeated so this block runs on its own.
USE ROLE ACCOUNTADMIN;
CREATE DATABASE INTERNAL_PRODUCT_DB FROM LISTING
  '<REPLACE: internal_listing_global_name>';
GRANT IMPORTED PRIVILEGES ON DATABASE INTERNAL_PRODUCT_DB
  TO ROLE SHARE_READER;
USE ROLE SHARE_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CONSUMER_WH;
SELECT COUNT(*) AS visible_rows
FROM INTERNAL_PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1;
-- Expected: VISIBLE_ROWS 2.

-- Discovery-only block, run separately as LISTING_BROWSER with secondary roles off.
-- Snowsight still shows Query in Workspaces to this role; the SQL below is the evidence.
-- SHOW AVAILABLE LISTINGS returns the listing with discover_only = true, and both
-- queries fail because LISTING_BROWSER is not in the access list and holds no grant.
-- USE ROLE LISTING_BROWSER;
-- USE SECONDARY ROLES NONE;
-- SHOW AVAILABLE LISTINGS IS_ORGANIZATION = TRUE;
-- SELECT COUNT(*) FROM INTERNAL_PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1;
-- SELECT COUNT(*)
-- FROM ORGDATACLOUD$INTERNAL$MERCHANT_INTERNAL_LISTING.PRODUCT.MERCHANT_DAILY_V1;
-- The uniform listing locator query returns 2 for SHARE_READER without a database.
