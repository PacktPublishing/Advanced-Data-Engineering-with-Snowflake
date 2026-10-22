-- Chapter 17: dedicated synthetic listing share
-- Relationship: separate stage; See README execution order; run only the stage being followed.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


USE ROLE SYSADMIN;
CREATE SHARE MARKETPLACE_LISTING_SHARE;
GRANT USAGE ON DATABASE PRODUCT_DB TO SHARE MARKETPLACE_LISTING_SHARE;
GRANT USAGE ON SCHEMA PRODUCT_DB.PRODUCT TO SHARE MARKETPLACE_LISTING_SHARE;
GRANT REFERENCE_USAGE ON DATABASE SOURCE_DB TO SHARE MARKETPLACE_LISTING_SHARE;
GRANT SELECT ON VIEW PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1
  TO SHARE MARKETPLACE_LISTING_SHARE;
SHOW GRANTS TO SHARE MARKETPLACE_LISTING_SHARE;
-- No listing is published here. Follow the draft worksheet in the README.
-- A share used by an active listing cannot simply be reused for another listing.
-- For BOTH external and internal draft exercises, create a distinct listing
-- product/share in the UI for the second exercise and inspect its grants.
