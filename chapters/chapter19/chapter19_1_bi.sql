-- Chapter 19: BI serving model, serving warehouse, and acceptance queries (sections 1.2 to 1.5)
-- Independent after common setup; do not run every section by default.
-- Prerequisites: chapter19_0_setup.sql. The multi-cluster statement needs Enterprise Edition or higher.
-- Validation: documentation checked October 2026; SQL blocks run live on the author's sandbox account on 2026-10-24.
-- Placeholder convention: <REPLACE: description> only for reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN only grants account privileges.
-- Commented statements are optional or edition-specific; every uncommented statement runs in order.

-- REPORTING VIEW BLOCK.
USE ROLE SYSADMIN;
USE WAREHOUSE BUILD_WH;
CREATE OR REPLACE VIEW
  ANALYTICS_DB.SERVING.DAILY_METRICS AS
SELECT event_date, merchant_id,
       COUNT(*) AS attempts,
       COUNT_IF(approved) AS approved_attempts,
       SUM(IFF(approved, amount_usd, 0))
         AS approved_amount_usd,
       MAX(source_updated_at) AS source_updated_at
FROM ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS
GROUP BY event_date, merchant_id;
GRANT SELECT ON VIEW
  ANALYTICS_DB.SERVING.DAILY_METRICS
  TO ROLE BI_READER;

-- READER VERIFICATION BLOCK: expect 12, 7, 675.00, 58.33.
USE ROLE BI_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BI_WH;
SELECT SUM(attempts) AS attempts,
       SUM(approved_attempts) AS approved_attempts,
       SUM(approved_amount_usd) AS approved_volume_usd,
       ROUND(100.0 * SUM(approved_attempts)
         / NULLIF(SUM(attempts), 0), 2) AS approval_pct
FROM ANALYTICS_DB.SERVING.DAILY_METRICS;

-- Expect four rows; rates must be calculated after aggregation in the BI model.
SELECT event_date, merchant_id, attempts, approved_attempts,
       approved_amount_usd,
       ROUND(100.0 * approved_attempts / NULLIF(attempts, 0), 2) AS approval_pct
FROM ANALYTICS_DB.SERVING.DAILY_METRICS
ORDER BY event_date, merchant_id;

-- Expect no duplicate grain rows.
SELECT event_date, merchant_id, COUNT(*) AS rows_at_grain
FROM ANALYTICS_DB.SERVING.DAILY_METRICS
GROUP BY event_date, merchant_id HAVING COUNT(*) <> 1;

-- SERVING WAREHOUSE BLOCK.
USE ROLE SYSADMIN;
ALTER WAREHOUSE BI_WH SET
  AUTO_SUSPEND = 300
  STATEMENT_TIMEOUT_IN_SECONDS = 120
  STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 60;
-- Enterprise Edition or higher only:
-- ALTER WAREHOUSE BI_WH SET MIN_CLUSTER_COUNT = 1
--   MAX_CLUSTER_COUNT = 3 SCALING_POLICY = 'STANDARD';
SHOW PARAMETERS LIKE 'STATEMENT%' IN WAREHOUSE BI_WH;
-- Expect 120 and 60 at the WAREHOUSE level; SHOW WAREHOUSES reports auto_suspend 300.
