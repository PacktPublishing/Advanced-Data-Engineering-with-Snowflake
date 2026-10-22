-- Chapter 17: private listing to the onboarded consumer
-- Relationship: separate stage; run after the direct-share revocation (2.3). Uses a dedicated share so the direct-share lab stays untouched.
-- Validation: executed in Snowflake on 2026-10-07 against a consumer in another organization.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.
-- Manifest fields: https://docs.snowflake.com/en/progaccess/listing-manifest-reference


USE ROLE SYSADMIN;
-- A share can back one listing. This share exists only for the private listing.
CREATE SHARE PARTNER_LISTING_SHARE;
GRANT USAGE ON DATABASE PRODUCT_DB TO SHARE PARTNER_LISTING_SHARE;
GRANT USAGE ON SCHEMA PRODUCT_DB.PRODUCT TO SHARE PARTNER_LISTING_SHARE;
GRANT REFERENCE_USAGE ON DATABASE SOURCE_DB TO SHARE PARTNER_LISTING_SHARE;
GRANT SELECT ON VIEW PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1
  TO SHARE PARTNER_LISTING_SHARE;
SHOW GRANTS TO SHARE PARTNER_LISTING_SHARE;
-- Expected: the same four grants as MERCHANT_SHARE and no private-table grant.

-- CREATE LISTING is an account-level privilege held by ACCOUNTADMIN by default.
-- Sample queries and the longer description are added in the Snowsight listing editor.
USE ROLE ACCOUNTADMIN;
CREATE EXTERNAL LISTING MERCHANT_PARTNER_LISTING
  SHARE PARTNER_LISTING_SHARE AS
$$
title: "Merchant 101 daily settlement, V1"
description: "Net settled value per merchant, date, and currency."
listing_terms:
  type: "OFFLINE"
targets:
  accounts: ["<REPLACE: consumer_org.consumer_account>"]
$$ PUBLISH = TRUE REVIEW = TRUE;
SHOW LISTINGS LIKE 'MERCHANT_PARTNER_LISTING';
-- Expected: one row with state PUBLISHED and the consumer account in target_accounts.
-- Unlike the organizational listing, this manifest publishes without a locations block.
