-- Chapter 17: local internal-role access
-- Relationship: separate stage; See README execution order; run only the stage being followed.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


USE ROLE USERADMIN;
CREATE ROLE INTERNAL_ANALYST;
SET lab_user = CURRENT_USER();
GRANT ROLE INTERNAL_ANALYST TO USER IDENTIFIER($lab_user);
GRANT ROLE INTERNAL_ANALYST TO ROLE SYSADMIN;
USE ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE PROVIDER_WH TO ROLE INTERNAL_ANALYST;
USE ROLE SYSADMIN;
GRANT USAGE ON DATABASE PRODUCT_DB
  TO ROLE INTERNAL_ANALYST;
GRANT USAGE ON SCHEMA PRODUCT_DB.PRODUCT
  TO ROLE INTERNAL_ANALYST;
GRANT SELECT ON VIEW
  PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1
  TO ROLE INTERNAL_ANALYST;
USE ROLE INTERNAL_ANALYST;
USE SECONDARY ROLES NONE;
USE WAREHOUSE PROVIDER_WH;
SELECT COUNT(*) AS visible_rows
FROM PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1;

-- Execute separately as an expected access failure:
-- SELECT * FROM SOURCE_DB.PRIVATE.MERCHANT_DAILY;
