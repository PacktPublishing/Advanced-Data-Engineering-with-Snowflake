-- Chapter 9: administrator bootstrap for sections 1 through 4.
-- Run chapter9_setup.sql first using the owner of the shared book objects.
-- Run this file once as a user allowed to use USERADMIN, SECURITYADMIN,
-- and ACCOUNTADMIN. No reader-specific identifiers need substitution:
-- the role is assigned to the user executing this bootstrap.
-- Role bootstrap runtime validation is pending; see the README validation notes.
-- This grants access without transferring ownership of existing objects.

USE SECONDARY ROLES NONE;
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS CH09_ORCHESTRATOR
    COMMENT = 'Chapter 9 task and Dynamic Table exercise owner';

USE ROLE SECURITYADMIN;
GRANT ROLE CH09_ORCHESTRATOR TO ROLE SYSADMIN;
SET ch09_reader = CURRENT_USER();
GRANT ROLE CH09_ORCHESTRATOR TO USER IDENTIFIER($ch09_reader);

-- These account-level privileges are granted once by the administrator.
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE CH09_ORCHESTRATOR;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE CH09_ORCHESTRATOR;

-- SECURITYADMIN can grant access even when an earlier chapter's objects
-- belong to another role. It does not take ownership of those objects.
USE ROLE SECURITYADMIN;
GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON DATABASE raw_db TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON DATABASE silver_db TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON DATABASE gold_db TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON DATABASE ops_db TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON SCHEMA raw_db.streaming TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON SCHEMA silver_db.transactions TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON SCHEMA gold_db.transactions TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON SCHEMA ops_db.pipelines TO ROLE CH09_ORCHESTRATOR;
GRANT CREATE TASK ON SCHEMA ops_db.pipelines TO ROLE CH09_ORCHESTRATOR;
GRANT CREATE STREAM ON SCHEMA raw_db.streaming TO ROLE CH09_ORCHESTRATOR;
GRANT CREATE DYNAMIC TABLE ON SCHEMA silver_db.transactions TO ROLE CH09_ORCHESTRATOR;
GRANT CREATE DYNAMIC TABLE ON SCHEMA gold_db.transactions TO ROLE CH09_ORCHESTRATOR;
GRANT SELECT, INSERT ON TABLE raw_db.streaming.raw_transactions TO ROLE CH09_ORCHESTRATOR;
GRANT SELECT, INSERT, UPDATE ON TABLE silver_db.transactions.transactions_clean TO ROLE CH09_ORCHESTRATOR;
GRANT SELECT, INSERT ON TABLE silver_db.transactions.rejected_transactions TO ROLE CH09_ORCHESTRATOR;
-- INSERT OVERWRITE requires DELETE as well as INSERT on the target.
GRANT SELECT, INSERT, DELETE ON TABLE gold_db.transactions.merchant_daily_revenue TO ROLE CH09_ORCHESTRATOR;
GRANT SELECT, INSERT ON TABLE ops_db.pipelines.pipeline_run_log TO ROLE CH09_ORCHESTRATOR;
GRANT USAGE ON PROCEDURE ops_db.pipelines.run_cleanse() TO ROLE CH09_ORCHESTRATOR;

USE ROLE CH09_ORCHESTRATOR;
USE WAREHOUSE BOOK_WH;
SELECT CURRENT_ROLE() AS exercise_role, CURRENT_SECONDARY_ROLES() AS secondary_roles;
SHOW GRANTS TO ROLE CH09_ORCHESTRATOR;
