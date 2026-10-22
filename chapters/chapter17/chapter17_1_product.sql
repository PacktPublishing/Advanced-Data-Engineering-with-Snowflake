-- Chapter 17: secure product and contract checks
-- Relationship: separate stage; Run provider setup first. Expected total 250 USD, 2 rows, no duplicate keys.
-- Validation: documentation checked September 2026; not executed in Snowflake.
-- External tooling: Snowsight SQL; CoCo CLI authenticated as in Chapter 6.
-- Placeholders: replace only <REPLACE: ...> with reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN
-- performs account grants/import administration only. Stop on any error.

USE ROLE SYSADMIN;
USE WAREHOUSE PROVIDER_WH;
CREATE SECURE VIEW
  PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1 AS
SELECT merchant_id, settlement_date, currency,
       net_settled_amount
FROM SOURCE_DB.PRIVATE.MERCHANT_DAILY
WHERE merchant_id = 101;


SELECT currency, COUNT(*) AS row_count,
       SUM(net_settled_amount) AS total_amount,
       COALESCE(COUNT_IF(merchant_id <> 101), 0) AS wrong_merchant
FROM PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1
GROUP BY currency;


SELECT merchant_id, settlement_date, currency,
       COUNT(*) AS rows_per_key
FROM PRODUCT_DB.PRODUCT.MERCHANT_DAILY_V1
GROUP BY merchant_id, settlement_date, currency
HAVING COUNT(*) > 1;
