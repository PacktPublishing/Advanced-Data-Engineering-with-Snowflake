-- Chapter 17: synthetic identity fixtures
-- Relationship: separate stage; Optional. Both accounts need installed Collaboration API. Run independently of sharing lab.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


USE ROLE SYSADMIN;
-- In owner account use 0. In partner account use 40.
SET identity_offset = <REPLACE: 0_for_owner_or_40_for_partner>;
-- CREATE without REPLACE prevents silent destruction of earlier fixtures.
EXECUTE IMMEDIATE $$
BEGIN
  CREATE DATABASE DCR_DB;
  CREATE SCHEMA DCR_DB.PRIVATE;
  CREATE WAREHOUSE DCR_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
  USE WAREHOUSE DCR_WH;
  CREATE TABLE DCR_DB.PRIVATE.CUSTOMERS AS
  SELECT BASE64_ENCODE(SHA2_BINARY(
    'person-' || TO_VARCHAR(n + $identity_offset) || '@example.invalid',
    256)) AS hashed_email
  FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n
        FROM TABLE(GENERATOR(ROWCOUNT => 60)));
  CREATE TABLE DCR_DB.PRIVATE.SMALL_CUSTOMERS AS
  SELECT BASE64_ENCODE(SHA2_BINARY(
    'small-' || TO_VARCHAR(n) || '@example.invalid', 256)) AS hashed_email
  FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n
        FROM TABLE(GENERATOR(ROWCOUNT => 5)));
END;
$$;
GRANT USAGE ON WAREHOUSE DCR_WH TO ROLE SAMOOHA_APP_ROLE;
SELECT COUNT(*) AS row_count, COUNT(DISTINCT hashed_email) AS distinct_hashes
FROM DCR_DB.PRIVATE.CUSTOMERS;
-- Expected 60,60. SMALL_CUSTOMERS must return 5,5 in both accounts.
-- Do NOT grant broad access to the application role here. Use CoCo's
-- metadata inventory to prepare the documented registration/link grants
-- for the installed API, then have the object owner apply those grants.
