-- Chapter 18: warehouse isolation (section "Verifying the warehouse boundary").
-- Run the setup script first. Independent of the role worksheets.
-- Prerequisites: sandbox account; standard warehouses from setup.
-- Validation: official Snowflake docs checked October 2026; SQL run live October 2026.
-- Placeholders: none.
-- Roles: SYSADMIN owns and configures warehouses; RISK_READER is a consumer.
-- The denial protects the settlement deadline: Risk must not reach PAYMENTS_WH.
-- (Run live in October 2026 in the reverse direction, PAYMENTS_BUILDER to RISK_WH;
-- reversed October 14, same mechanism, pending a live run.)
-- Stop on every error except the final, explicitly marked denial statement.

-- BLOCK: workload-class settings
USE ROLE SYSADMIN;
ALTER WAREHOUSE PAYMENTS_WH SET
  STATEMENT_TIMEOUT_IN_SECONDS = 1800;
ALTER WAREHOUSE RISK_WH SET
  MAX_CONCURRENCY_LEVEL = 4
  STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 60;
SHOW PARAMETERS IN WAREHOUSE PAYMENTS_WH;
SHOW PARAMETERS IN WAREHOUSE RISK_WH;

-- BLOCK: warehouse denial; final statement MUST fail
USE ROLE RISK_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE RISK_WH;
SELECT CURRENT_WAREHOUSE();
USE WAREHOUSE PAYMENTS_WH;
-- EXPECT: RISK_WH, then SQL compilation error (observed October 2026 for the
-- reverse direction): Object does not exist, or operation cannot be performed.
-- Snowflake returns the same message for a missing or an unauthorized warehouse.
