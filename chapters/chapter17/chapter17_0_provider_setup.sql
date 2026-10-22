-- Chapter 17: provider fixture setup
-- Relationship: separate stage; See README execution order; run only the stage being followed.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.


USE ROLE SYSADMIN;
-- The whole bootstrap is one block. Existing databases abort before changes.
EXECUTE IMMEDIATE $$
DECLARE
  existing_count INTEGER;
  existing_lab EXCEPTION (-20001, 'The lab database exists. Inspect it before rerunning.');
BEGIN
  SHOW DATABASES;
  SELECT COUNT(*) INTO :existing_count
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
  WHERE "name" IN ('SOURCE_DB', 'PRODUCT_DB');
  IF (existing_count > 0) THEN
    RAISE existing_lab;
  END IF;
  CREATE DATABASE SOURCE_DB;
  CREATE SCHEMA SOURCE_DB.PRIVATE;
  CREATE DATABASE PRODUCT_DB;
  CREATE SCHEMA PRODUCT_DB.PRODUCT;
  CREATE WAREHOUSE IF NOT EXISTS PROVIDER_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
  USE WAREHOUSE PROVIDER_WH;
  CREATE TABLE SOURCE_DB.PRIVATE.MERCHANT_DAILY (
    merchant_id NUMBER(10,0), settlement_date DATE,
    currency VARCHAR(3), net_settled_amount NUMBER(18,2),
    operational_note VARCHAR
  );
  INSERT INTO SOURCE_DB.PRIVATE.MERCHANT_DAILY VALUES
    (101, '2026-09-01', 'USD', 100.00, 'Synthetic internal note A'),
    (101, '2026-09-02', 'USD', 150.00, 'Synthetic internal note B'),
    (202, '2026-09-01', 'USD', 900.00, 'Synthetic internal note C'),
    (202, '2026-09-02', 'CAD', 800.00, 'Synthetic internal note D');
END;
$$;
-- Needed only to delegate share creation to the lab object owner.
USE ROLE ACCOUNTADMIN;
GRANT CREATE SHARE ON ACCOUNT TO ROLE SYSADMIN;
USE ROLE SYSADMIN;
SELECT COUNT(*) AS source_rows
FROM SOURCE_DB.PRIVATE.MERCHANT_DAILY;
-- Expected: 4. Warehouse suspends after 60 seconds without activity.
