-- Chapter 19: Native App version, release directive, and local installation (section 3.2)
-- Independent after the provider preparation in chapter19_3_native_app.sql.
-- Prerequisites: provider preparation and three uploaded files; see README.
-- Validation: documentation checked October 2026; not executed on a live Snowflake account.
-- Placeholder convention: <REPLACE: description> only for reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN only grants account privileges.
-- Stop on any error. CREATE statements deliberately fail on existing lab tables/services.
-- New application packages have release channels enabled by default, so a version is
-- registered and placed on a channel; ADD VERSION ... USING is not supported for them.

-- RELEASE BLOCK.
USE ROLE SYSADMIN;
ALTER APPLICATION PACKAGE ANALYTICS_PKG
  REGISTER VERSION V1 USING '@ANALYTICS_DB.APP_CODE.SRC';
ALTER APPLICATION PACKAGE ANALYTICS_PKG
  MODIFY RELEASE CHANNEL DEFAULT ADD VERSION V1;
ALTER APPLICATION PACKAGE ANALYTICS_PKG
  MODIFY RELEASE CHANNEL DEFAULT
  SET DEFAULT RELEASE DIRECTIVE VERSION = V1 PATCH = 0;
CREATE APPLICATION ANALYTICS_APP
  FROM APPLICATION PACKAGE ANALYTICS_PKG;
GRANT APPLICATION ROLE ANALYTICS_APP.APP_READER
  TO ROLE BI_READER;

-- SQL acceptance under the application reader role: expect 4, 675.00.
USE ROLE BI_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BI_WH;
SELECT COUNT(*) AS rows_in_app,
       SUM(approved_amount_usd) AS approved_volume_usd
FROM ANALYTICS_APP.APP_PUBLIC.DAILY_METRICS;
-- UI verification: Data Products > Apps > ANALYTICS_APP.
-- Choose BI_WH if prompted. M100 must show 375.00 and 62.5%.

-- PRIVATE LISTING TEMPLATE (section 3.3; needs a second account; deliberately commented).
-- External distribution also needs DISTRIBUTION = EXTERNAL and a passed security review.
-- The listing pattern, manifest fields, and consumer steps follow Chapter 17's private listing.
-- USE ROLE ACCOUNTADMIN;
-- ALTER APPLICATION PACKAGE ANALYTICS_PKG SET DISTRIBUTION = EXTERNAL;
-- CREATE EXTERNAL LISTING ANALYTICS_APP_LISTING
--   APPLICATION PACKAGE ANALYTICS_PKG AS
-- $$
-- title: "Payment performance dashboard, V1"
-- description: "Merchant-day approval metrics from a synthetic fixture."
-- listing_terms:
--   type: "OFFLINE"
-- targets:
--   accounts: ["<REPLACE: consumer_org.consumer_account>"]
-- $$ PUBLISH = TRUE REVIEW = TRUE;
