-- =========================================================================
-- Chapter 11: remove the objects this chapter's setup created
-- =========================================================================
-- REVIEW ONLY. Run by hand after you finish the chapter. It drops only the
-- objects sql/setup.sql created; it does not touch Chapter 9 or Chapter 10
-- objects.
-- =========================================================================

USE ROLE SECURITYADMIN;
REVOKE INSERT, DELETE ON TABLE gold_db.transactions.merchant_daily_revenue FROM ROLE TRANSFORMER_RL;

USE ROLE ACCOUNTADMIN;
DROP USER IF EXISTS SVC_ORCHESTRATOR;

-- Table + stage were created as ACCOUNTADMIN (RAW_DB.STREAMING is
-- ACCOUNTADMIN-owned). SYSADMIN DROP would fail with insufficient privilege.
DROP STAGE IF EXISTS raw_db.streaming.ml_scores_stage;
DROP TABLE IF EXISTS raw_db.streaming.fraud_scores;
REVOKE USAGE ON INTEGRATION techflow_ml_integration FROM ROLE SYSADMIN;
DROP STORAGE INTEGRATION IF EXISTS techflow_ml_integration;

-- setup.sql granted TRANSFORMER_RL to SYSADMIN; DROP ROLE requires that gone.
REVOKE ROLE TRANSFORMER_RL FROM ROLE SYSADMIN;

USE ROLE USERADMIN;
DROP ROLE IF EXISTS TRANSFORMER_RL;
