-- =========================================================================
-- Chapter 8 Section 4: External stage setup (S3 + storage integration)
-- =========================================================================
-- Run as ACCOUNTADMIN (storage integrations are account-level objects).
-- Placeholders: search for <REPLACE: ...> and substitute your values.
-- After phase 1 (CREATE STORAGE INTEGRATION), run
-- DESCRIBE to extract the AWS IAM user ARN and external ID that Snowflake
-- generated. Those go back into Terraform (phase 2) so the IAM role trust
-- policy lets Snowflake assume it.
-- =========================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;

-- Phase 1: storage integration
CREATE OR REPLACE STORAGE INTEGRATION lake_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<REPLACE: your-aws-account-id>:role/SnowflakeStageRole'
  STORAGE_ALLOWED_LOCATIONS = ('s3://<REPLACE: your-lake-bucket>/');

-- Grab STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from output:
DESCRIBE INTEGRATION lake_int;

-- Phase 2 (after Terraform re-apply): create the stage
-- CREATE STAGE gold_db.transactions.lake_stage
--   STORAGE_INTEGRATION = lake_int
--   URL = 's3://<REPLACE: your-lake-bucket>/'
--   FILE_FORMAT = (TYPE = PARQUET);
-- LIST @gold_db.transactions.lake_stage;
