-- Chapter 17: organizational listing for the Internal Marketplace
-- Relationship: separate stage; run in the PROVIDER account after chapter17_4_internal_mesh.sql. The consumer account creates LISTING_BROWSER first (chapter17_4_org_listing_consumer.sql, part 1).
-- Validation: executed in Snowflake on 2026-10-05, provider and consumer in one organization.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.
-- Manifest fields: https://docs.snowflake.com/en/user-guide/collaboration/listings/organizational/org-listing-manifest-reference


USE ROLE SYSADMIN;
-- A share can back one listing. This share exists only for the internal listing.
CREATE SHARE INTERNAL_LISTING_SHARE;
GRANT USAGE ON DATABASE PRODUCT_DB TO SHARE INTERNAL_LISTING_SHARE;
GRANT USAGE ON SCHEMA PRODUCT_DB.PRODUCT TO SHARE INTERNAL_LISTING_SHARE;
GRANT REFERENCE_USAGE ON DATABASE SOURCE_DB TO SHARE INTERNAL_LISTING_SHARE;
GRANT SELECT ON VIEW PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1
  TO SHARE INTERNAL_LISTING_SHARE;
SHOW GRANTS TO SHARE INTERNAL_LISTING_SHARE;
-- Expected: four grants and no private-table grant.

-- CREATE ORGANIZATION LISTING is an account-level privilege held by ACCOUNTADMIN.
-- The account name is the consumer's account name alone, without the organization.
-- locations is required to publish, although the manifest reference marks it optional.
-- Write the provider's region with the PUBLIC. prefix, for example PUBLIC.AWS_US_WEST_2.
USE ROLE ACCOUNTADMIN;
CREATE ORGANIZATION LISTING MERCHANT_INTERNAL_LISTING
  SHARE INTERNAL_LISTING_SHARE AS
$$
title: "Merchant 101 daily settlement, V1"
description: "Payments domain product. Synthetic, USD, no refresh."
organization_targets:
  discovery:
    - account: "<REPLACE: consumer_account_name>"
      roles: ["ACCOUNTADMIN", "SHARE_READER", "LISTING_BROWSER"]
  access:
    - account: "<REPLACE: consumer_account_name>"
      roles: ["ACCOUNTADMIN", "SHARE_READER"]
support_contact: "<REPLACE: payments_support_email>"
approver_contact: "<REPLACE: payments_approver_email>"
locations:
  access_regions:
    - name: "<REPLACE: PUBLIC.provider_region>"
$$ PUBLISH = TRUE;
SHOW LISTINGS LIKE 'MERCHANT_INTERNAL_LISTING';
-- Expected: one row with state PUBLISHED. LISTING_BROWSER can discover the listing;
-- only the access roles can get or query the data product.
