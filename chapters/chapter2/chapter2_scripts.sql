-- =============================================================================
-- Chapter 2: Building an Open Lakehouse with Apache Iceberg
-- All SQL scripts from the chapter, organized by section.
--
-- Prerequisites:
--   - Run setup/snowflake_setup.sql first (creates UTIL db, BOOK_WH, MCP, PAT)
--   - Run setup/terraform/aws/ to create AWS infra (S3, IAM, Glue, S3 Tables)
--   - Complete the two-phase IAM trust setup (see setup/SETUP.md)
--
-- Placeholders: search for <REPLACE: ...> and substitute with your values.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;

-- =============================================================================
-- Chapter database + schemas
-- =============================================================================

CREATE DATABASE IF NOT EXISTS MEDCORE_DEMO
    COMMENT = 'MedCore Health Systems demo — Chapter 2';

CREATE SCHEMA IF NOT EXISTS MEDCORE_DEMO.CLINICAL;
CREATE SCHEMA IF NOT EXISTS MEDCORE_DEMO.ANALYTICS;
CREATE SCHEMA IF NOT EXISTS MEDCORE_DEMO.CLINICAL_RESEARCH;

USE DATABASE MEDCORE_DEMO;
USE SCHEMA CLINICAL;


-- ============================================================================
-- Section 3.1: External Volumes for AWS S3
-- Run this BEFORE sections 2.x (tables need a volume to exist first)
-- ============================================================================

-- Step 1: Create the external volume
CREATE OR REPLACE EXTERNAL VOLUME medcore_aws_volume
    STORAGE_LOCATIONS = (
        (
            NAME = 'medcore-s3-primary'
            STORAGE_PROVIDER = 'S3'
            STORAGE_BASE_URL = 's3://<REPLACE: your-bucket-name>/iceberg/'
            STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<REPLACE: aws-account-id>:role/SnowflakeIcebergRole'
            STORAGE_AWS_EXTERNAL_ID = 'medcore_iceberg_ext_id'
        )
    )
    ALLOW_WRITES = TRUE;

-- Step 2: Retrieve Snowflake's IAM identity (copy ARN + external ID for Terraform Phase 2)
DESCRIBE EXTERNAL VOLUME medcore_aws_volume;

-- Step 4: Verify (run AFTER Terraform Phase 2 updates the IAM trust policy)
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('medcore_aws_volume');


-- ============================================================================
-- Section 3.2: External Volumes for Azure Blob Storage
-- (Azure only — included for reference, not testable on AWS accounts)
-- ============================================================================

-- CREATE OR REPLACE EXTERNAL VOLUME medcore_azure_volume
--     STORAGE_LOCATIONS = (
--         (
--             NAME = 'medcore-azure-eastus'
--             STORAGE_PROVIDER = 'AZURE'
--             STORAGE_BASE_URL = 'azure://medcorelakehouse.blob.core.windows.net/iceberg/'
--             AZURE_TENANT_ID = '<your-azure-tenant-id>'
--         )
--     )
--     ALLOW_WRITES = TRUE;
--
-- DESCRIBE EXTERNAL VOLUME medcore_azure_volume;
-- SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('medcore_azure_volume');


-- ============================================================================
-- Section 3.3: Setting Default External Volumes
-- ============================================================================

-- Set default at account level
ALTER ACCOUNT SET EXTERNAL_VOLUME = 'medcore_aws_volume';

-- Override at database level for specific use cases
ALTER DATABASE MEDCORE_DEMO SET EXTERNAL_VOLUME = 'medcore_aws_volume';

-- Override at schema level
ALTER SCHEMA MEDCORE_DEMO.CLINICAL_RESEARCH SET EXTERNAL_VOLUME = 'medcore_aws_volume';


-- ============================================================================
-- Section 3.4: Catalog Integrations — AWS Glue (REST Endpoint)
-- ============================================================================

CREATE OR REPLACE CATALOG INTEGRATION medcore_glue_integration
    CATALOG_SOURCE = ICEBERG_REST
    TABLE_FORMAT = ICEBERG
    CATALOG_NAMESPACE = 'clinical_research'
    REST_CONFIG = (
        CATALOG_URI = 'https://glue.<REPLACE: aws-region>.amazonaws.com/iceberg'
        CATALOG_API_TYPE = AWS_GLUE
        CATALOG_NAME = '<REPLACE: aws-account-id>'
    )
    REST_AUTHENTICATION = (
        TYPE = SIGV4
        SIGV4_IAM_ROLE = 'arn:aws:iam::<REPLACE: aws-account-id>:role/SnowflakeGlueRole'
        SIGV4_SIGNING_REGION = '<REPLACE: aws-region>'
    )
    ENABLED = TRUE;

-- Retrieve IAM identity (copy ARN + external ID for Terraform Phase 2)
DESCRIBE CATALOG INTEGRATION medcore_glue_integration;


-- ============================================================================
-- Section 3.4: Catalog Integrations — Open Catalog (Polaris)
-- (Reference only — requires Snowflake Open Catalog account)
-- ============================================================================

-- CREATE OR REPLACE CATALOG INTEGRATION medcore_polaris_integration
--     CATALOG_SOURCE = ICEBERG_REST
--     TABLE_FORMAT = ICEBERG
--     CATALOG_NAMESPACE = 'production'
--     REST_CONFIG = (
--         CATALOG_URI = 'https://<your-org>.snowflakecomputing.com/polaris/api/catalog'
--         WAREHOUSE = 'medcore_warehouse'
--     )
--     REST_AUTHENTICATION = (
--         TYPE = BEARER
--         OAUTH_CLIENT_ID = '<client-id>'
--         OAUTH_CLIENT_SECRET = '<client-secret>'
--         OAUTH_ALLOWED_SCOPES = ('PRINCIPAL_ROLE:ALL')
--     )
--     ENABLED = TRUE;


-- ============================================================================
-- Section 2.1: Snowflake-Managed Iceberg Tables
-- ============================================================================

CREATE OR REPLACE ICEBERG TABLE patient_encounters (
    encounter_id    STRING,
    patient_id      STRING,
    facility_code   STRING,
    encounter_date  DATE,
    diagnosis_code  STRING,
    provider_id     STRING,
    charge_amount   NUMBER(12,2),
    inserted_at     TIMESTAMP_NTZ
)
    CATALOG = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'medcore_aws_volume'
    BASE_LOCATION = 'clinical/patient_encounters'
    STORAGE_SERIALIZATION_POLICY = 'OPTIMIZED';


-- ============================================================================
-- Section 2.2: Adding Partitions
-- ============================================================================

CREATE OR REPLACE ICEBERG TABLE patient_encounters_partitioned (
    encounter_id    STRING,
    patient_id      STRING,
    facility_code   STRING,
    encounter_date  DATE,
    diagnosis_code  STRING,
    provider_id     STRING,
    charge_amount   NUMBER(12,2),
    inserted_at     TIMESTAMP_NTZ
)
    PARTITION BY (facility_code, MONTH(encounter_date))
    CATALOG = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'medcore_aws_volume'
    BASE_LOCATION = 'clinical/patient_encounters_partitioned'
    STORAGE_SERIALIZATION_POLICY = 'COMPATIBLE';


-- ============================================================================
-- Section 2.3: Loading Data into Iceberg Tables
-- ============================================================================

-- Bulk load from staging (reference — requires a stage with Parquet files)
-- COPY INTO patient_encounters
-- FROM @medcore_staging_stage/encounters/
--     FILE_FORMAT = (TYPE = PARQUET)
--     MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

-- Insert synthetic test data
INSERT INTO patient_encounters (
    encounter_id, patient_id, facility_code,
    encounter_date, diagnosis_code, provider_id, charge_amount
)
SELECT
    'ENC-' || LPAD(SEQ4()::STRING, 8, '0'),
    'PAT-' || LPAD(UNIFORM(1, 5000, RANDOM())::STRING, 6, '0'),
    'FAC-' || LPAD(UNIFORM(1, 22, RANDOM())::STRING, 3, '0'),
    DATEADD(day, -UNIFORM(0, 365, RANDOM()), '2026-02-22'::DATE),
    'ICD-' || UNIFORM(1000, 9999, RANDOM())::STRING,
    'PRV-' || LPAD(UNIFORM(1, 200, RANDOM())::STRING, 4, '0'),
    ROUND(UNIFORM(50, 25000, RANDOM())::NUMBER(12,2) / 100, 2)
FROM TABLE(GENERATOR(ROWCOUNT => 1000));

-- Insert from another table (reference — requires raw_encounters to exist)
-- INSERT INTO patient_encounters
-- SELECT * FROM raw_encounters
-- WHERE encounter_date >= '2026-01-01';

-- Merge for CDC patterns: create a staging table + merge
CREATE OR REPLACE TEMPORARY TABLE staged_encounters AS
SELECT
    encounter_id,
    patient_id,
    facility_code,
    encounter_date,
    'ICD-' || UNIFORM(1000, 9999, RANDOM())::STRING AS diagnosis_code,
    provider_id,
    ROUND(charge_amount * 1.05, 2) AS charge_amount,
    CURRENT_TIMESTAMP() AS updated_at
FROM patient_encounters
SAMPLE (10 ROWS);

MERGE INTO patient_encounters target
USING staged_encounters source
    ON target.encounter_id = source.encounter_id
WHEN MATCHED AND source.updated_at > target.inserted_at
    THEN UPDATE SET
        diagnosis_code = source.diagnosis_code,
        charge_amount  = source.charge_amount,
        inserted_at    = CURRENT_TIMESTAMP()
WHEN NOT MATCHED
    THEN INSERT (encounter_id, patient_id, facility_code,
                 encounter_date, diagnosis_code, provider_id,
                 charge_amount)
    VALUES (source.encounter_id, source.patient_id, source.facility_code,
            source.encounter_date, source.diagnosis_code, source.provider_id,
            source.charge_amount);


-- ============================================================================
-- Section 2.4: Snowflake-Managed — What Happens Under the Hood
-- ============================================================================

-- Check table metadata
SELECT SYSTEM$GET_ICEBERG_TABLE_INFORMATION('MEDCORE_DEMO.CLINICAL.PATIENT_ENCOUNTERS') AS iceberg_info;

-- View snapshots (time travel) — adjust timestamp to a time after your INSERT
SELECT *
FROM patient_encounters AT(OFFSET => -60);


-- ============================================================================
-- Section 2.5: Externally Managed Iceberg Tables
-- (Requires Glue catalog integration from Section 3.4 + Terraform Glue table)
-- ============================================================================

USE SCHEMA MEDCORE_DEMO.CLINICAL_RESEARCH;

-- Create an Iceberg table linked to AWS Glue
CREATE OR REPLACE ICEBERG TABLE genomic_variants
    EXTERNAL_VOLUME = 'medcore_aws_volume'
    CATALOG = 'medcore_glue_integration'
    CATALOG_TABLE_NAME = 'genomic_variants'
    CATALOG_NAMESPACE = 'clinical_research';

-- Refresh metadata from external catalog
ALTER ICEBERG TABLE genomic_variants REFRESH;

-- Query with full Snowflake SQL
SELECT variant_id, gene_name, clinical_significance
FROM genomic_variants
WHERE chromosome = 'chr17'
  AND clinical_significance = 'Pathogenic';

USE SCHEMA MEDCORE_DEMO.CLINICAL;


-- ============================================================================
-- Section 2.6: Catalog-Linked Databases
-- ============================================================================

CREATE OR REPLACE DATABASE genomics_db
    LINKED_CATALOG = (
        CATALOG = 'medcore_glue_integration'
    )
    EXTERNAL_VOLUME = 'medcore_aws_volume'
    COMMENT = 'Catalog-linked database synced from AWS Glue';


-- ============================================================================
-- Section 2.7: Dynamic Iceberg Tables
-- ============================================================================

CREATE OR REPLACE DYNAMIC ICEBERG TABLE encounter_metrics
    TARGET_LAG = '1 hour'
    WAREHOUSE = 'BOOK_WH'
    EXTERNAL_VOLUME = 'medcore_aws_volume'
    CATALOG = 'SNOWFLAKE'
    BASE_LOCATION = 'analytics/encounter_metrics'
AS
SELECT
    facility_code,
    DATE_TRUNC('month', encounter_date) AS encounter_month,
    COUNT(*) AS total_encounters,
    COUNT(DISTINCT patient_id) AS unique_patients,
    SUM(charge_amount) AS total_charges,
    AVG(charge_amount) AS avg_charge
FROM patient_encounters
GROUP BY facility_code, DATE_TRUNC('month', encounter_date);


-- ============================================================================
-- Section 3.5: Verifying Your Setup End-to-End (Smoke Test)
-- ============================================================================

-- 1. Verify external volume connectivity
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('medcore_aws_volume');

-- 2. Create a test table
CREATE OR REPLACE ICEBERG TABLE iceberg_smoke_test (
    id INT,
    test_value STRING
)
    CATALOG = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'medcore_aws_volume'
    BASE_LOCATION = 'test/smoke_test';

-- 3. Write and read data
INSERT INTO iceberg_smoke_test VALUES (1, 'hello_iceberg');
SELECT * FROM iceberg_smoke_test;

-- 4. Verify files exist in storage (check your cloud console)
-- Files should appear at: s3://<bucket>/iceberg/test/smoke_test/data/
-- Metadata at: s3://<bucket>/iceberg/test/smoke_test/metadata/

-- 5. Clean up
DROP TABLE iceberg_smoke_test;


-- ============================================================================
-- Section 4.1: Microsoft Fabric and OneLake
-- (Azure only — reference scripts, not testable on AWS)
-- ============================================================================

-- CREATE OR REPLACE EXTERNAL VOLUME medcore_onelake_volume
--     STORAGE_LOCATIONS = (
--         (
--             NAME = 'medcore-onelake'
--             STORAGE_PROVIDER = 'AZURE'
--             STORAGE_BASE_URL = 'azure://onelake.dfs.fabric.microsoft.com/<workspace-id>/<lakehouse-id>/Tables/'
--             AZURE_TENANT_ID = '<your-azure-tenant-id>'
--         )
--     )
--     ALLOW_WRITES = TRUE;


-- ============================================================================
-- Section 4.2: AWS S3 Tables — Catalog Integration
-- S3 Tables are accessed through the SageMaker Lakehouse Iceberg REST endpoint
-- (AWS Glue). CATALOG_NAME uses the format:
--   <aws-account-id>:s3tablescatalog/<table-bucket-name>
-- ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS enables Lake Formation
-- credential vending for data access.
-- ============================================================================

CREATE OR REPLACE CATALOG INTEGRATION s3_tables_integration
    CATALOG_SOURCE = ICEBERG_REST
    TABLE_FORMAT = ICEBERG
    CATALOG_NAMESPACE = '<REPLACE: s3-tables-namespace>'
    REST_CONFIG = (
        CATALOG_URI = 'https://glue.<REPLACE: aws-region>.amazonaws.com/iceberg'
        CATALOG_API_TYPE = AWS_GLUE
        CATALOG_NAME = '<REPLACE: aws-account-id>:s3tablescatalog/<REPLACE: table-bucket-name>'
        ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS
    )
    REST_AUTHENTICATION = (
        TYPE = SIGV4
        SIGV4_IAM_ROLE = 'arn:aws:iam::<REPLACE: aws-account-id>:role/SnowflakeS3TablesRole'
        SIGV4_SIGNING_REGION = '<REPLACE: aws-region>'
    )
    REFRESH_INTERVAL_SECONDS = 120
    ENABLED = TRUE;

DESCRIBE CATALOG INTEGRATION s3_tables_integration;


-- ============================================================================
-- Section 4.3: Databricks Unity Catalog
-- (Reference only — requires Databricks workspace)
-- ============================================================================

-- CREATE OR REPLACE CATALOG INTEGRATION unity_catalog_integration
--     CATALOG_SOURCE = ICEBERG_REST
--     TABLE_FORMAT = ICEBERG
--     CATALOG_NAMESPACE = 'medcore_catalog.clinical'
--     REST_CONFIG = (
--         CATALOG_URI = 'https://<databricks-workspace>.databricks.com/api/2.1/unity-catalog/iceberg'
--         WAREHOUSE = 'medcore_catalog'
--     )
--     REST_AUTHENTICATION = (
--         TYPE = BEARER
--         OAUTH_CLIENT_ID = '<client-id>'
--         OAUTH_CLIENT_SECRET = '<client-secret>'
--         OAUTH_ALLOWED_SCOPES = ('all-apis')
--     )
--     ENABLED = TRUE;


-- ============================================================================
-- Section 4.2: PySpark Configurations (Reference — not SQL)
-- ============================================================================

-- # PySpark: reading Snowflake-managed Iceberg tables via Horizon REST API
-- spark = SparkSession.builder \
--     .config("spark.sql.catalog.snowflake_catalog",
--             "org.apache.iceberg.spark.SparkCatalog") \
--     .config("spark.sql.catalog.snowflake_catalog.type", "rest") \
--     .config("spark.sql.catalog.snowflake_catalog.uri",
--             "https://<account>.snowflakecomputing.com/polaris/api/catalog") \
--     .config("spark.sql.catalog.snowflake_catalog.credential",
--             "<oauth-token>") \
--     .config("spark.sql.catalog.snowflake_catalog.warehouse",
--             "<database-name>") \
--     .getOrCreate()
--
-- # PySpark: using AWS Glue as the catalog
-- spark = SparkSession.builder \
--     .config("spark.sql.catalog.glue_catalog",
--             "org.apache.iceberg.spark.SparkCatalog") \
--     .config("spark.sql.catalog.glue_catalog.catalog-impl",
--             "org.apache.iceberg.aws.glue.GlueCatalog") \
--     .config("spark.sql.catalog.glue_catalog.warehouse",
--             "s3://medcore-lakehouse-prod/iceberg/") \
--     .getOrCreate()
