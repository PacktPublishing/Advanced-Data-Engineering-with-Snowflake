-- =========================================================================
-- Chapter 11, Technical Requirements: one-time setup for external orchestration
-- =========================================================================
-- REVIEW ONLY until you decide to run it. Every statement below mutates the
-- account. Automated tests in this chapter never run this file.
--
-- Creates TRANSFORMER_RL (this chapter's least-privilege functional role),
-- the SVC_ORCHESTRATOR service user, the fraud-score landing table and
-- external stage, and the grants the orchestrators need.
-- =========================================================================

-- 1. Functional role. USERADMIN creates roles; SYSADMIN receives it so
--    administrators can see what the pipeline builds.
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS TRANSFORMER_RL
    COMMENT = 'Chapter 11: least-privilege role for Airflow/Prefect/Dagster + dbt';

GRANT ROLE TRANSFORMER_RL TO ROLE SYSADMIN;

-- 2. Service user for the orchestrators. TYPE = SERVICE blocks password auth
--    entirely, so the user authenticates only with its key pair.
USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS SVC_ORCHESTRATOR
    TYPE = SERVICE
    DEFAULT_ROLE = TRANSFORMER_RL
    DEFAULT_WAREHOUSE = BOOK_WH
    COMMENT = 'Chapter 11 external orchestration service user (Airflow/Prefect/Dagster)';

GRANT ROLE TRANSFORMER_RL TO USER SVC_ORCHESTRATOR;

-- Register the public half of the key pair generated in Chapter 10. Paste the
-- key body only (no PEM header/footer, no line breaks). Leave this commented
-- until you have a real key; a placeholder value fails ALTER USER.
-- ALTER USER SVC_ORCHESTRATOR SET RSA_PUBLIC_KEY = '<BASE64_PUBLIC_KEY_BODY>';

-- 3. Storage integration (account-level) then landing table + stage.
CREATE STORAGE INTEGRATION IF NOT EXISTS techflow_ml_integration
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<REPLACE: your-aws-account-id>:role/techflow-ml-role'
    STORAGE_ALLOWED_LOCATIONS = ('s3://techflow-ml/scores/');

GRANT USAGE ON INTEGRATION techflow_ml_integration TO ROLE SYSADMIN;

-- Snowflake IAM user + external ID for the IAM role trust policy (Terraform
-- phase 2: snowflake_stage_iam_arn / snowflake_stage_ext_id).
DESC STORAGE INTEGRATION techflow_ml_integration;

-- Schema RAW_DB.STREAMING is ACCOUNTADMIN-owned on the book account (Openflow /
-- streaming ingest). SYSADMIN cannot CREATE TABLE there.
-- merchant_id is STRING to match silver_db.transactions.transactions_clean and
-- gold_db.transactions.merchant_daily_revenue, whose ids are values like
-- 'MERCH_GROC_1'. A NUMBER column here would make the reverse-ETL join fail with
-- "Numeric value 'MERCH_GROC_1' is not recognized".
CREATE TABLE IF NOT EXISTS raw_db.streaming.fraud_scores (
    merchant_id STRING,
    risk_score  FLOAT,
    scored_date DATE
);

CREATE STAGE IF NOT EXISTS raw_db.streaming.ml_scores_stage
    STORAGE_INTEGRATION = techflow_ml_integration
    URL = 's3://techflow-ml/scores/'
    FILE_FORMAT = (TYPE = PARQUET);

-- 4. Grants this chapter needs on TRANSFORMER_RL.
-- CREATE SCHEMA on a database does not imply USAGE or CREATE VIEW on a schema
-- that already exists (Chapter 10's DCM owner created gold_db.transactions).
USE ROLE SECURITYADMIN;

GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE TRANSFORMER_RL;

GRANT USAGE ON DATABASE raw_db TO ROLE TRANSFORMER_RL;
GRANT USAGE ON DATABASE silver_db TO ROLE TRANSFORMER_RL;
GRANT USAGE ON DATABASE gold_db TO ROLE TRANSFORMER_RL;
GRANT USAGE ON DATABASE ops_db TO ROLE TRANSFORMER_RL;

GRANT USAGE ON SCHEMA raw_db.streaming TO ROLE TRANSFORMER_RL;
GRANT USAGE ON SCHEMA silver_db.transactions TO ROLE TRANSFORMER_RL;
GRANT USAGE ON SCHEMA gold_db.transactions TO ROLE TRANSFORMER_RL;
GRANT USAGE ON SCHEMA ops_db.pipelines TO ROLE TRANSFORMER_RL;

-- INSERT OVERWRITE and the partition-scoped DELETE+INSERT both remove rows.
GRANT INSERT, DELETE ON TABLE gold_db.transactions.merchant_daily_revenue TO ROLE TRANSFORMER_RL;
GRANT INSERT ON TABLE raw_db.streaming.fraud_scores TO ROLE TRANSFORMER_RL;
GRANT USAGE ON PROCEDURE ops_db.pipelines.run_cleanse() TO ROLE TRANSFORMER_RL;
GRANT USAGE ON STAGE raw_db.streaming.ml_scores_stage TO ROLE TRANSFORMER_RL;
GRANT SELECT ON TABLE raw_db.streaming.fraud_scores TO ROLE TRANSFORMER_RL;
GRANT SELECT ON TABLE silver_db.transactions.transactions_clean TO ROLE TRANSFORMER_RL;
GRANT SELECT ON TABLE gold_db.transactions.merchant_daily_revenue TO ROLE TRANSFORMER_RL;

-- dbt materializes into the existing gold/silver transaction schemas; CREATE
-- SCHEMA on the database is not enough for CREATE VIEW on those schemas.
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA gold_db.transactions TO ROLE TRANSFORMER_RL;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA silver_db.transactions TO ROLE TRANSFORMER_RL;
GRANT CREATE SCHEMA ON DATABASE silver_db TO ROLE TRANSFORMER_RL;
GRANT CREATE SCHEMA ON DATABASE gold_db TO ROLE TRANSFORMER_RL;

-- QUERY_ATTRIBUTION_HISTORY lives in ACCOUNT_USAGE. This grant requires
-- ACCOUNTADMIN (or a role that already holds imported privileges on SNOWFLAKE).
USE ROLE ACCOUNTADMIN;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE TRANSFORMER_RL;
