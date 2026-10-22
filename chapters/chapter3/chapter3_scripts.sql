-- =============================================================================
-- Chapter 3: Building Batch Data Ingestion Patterns
-- All SQL/Python scripts from the chapter, organized by section.
--
-- Prerequisites:
--   - Run setup/snowflake_setup.sql first (creates UTIL db, BOOK_WH, MCP, PAT)
--   - Run setup/terraform/aws/ for AWS infra (S3 bucket, IAM roles)
--   - Chapter 2 external volume (medcore_aws_volume) already exists
--
-- Placeholders: search for <REPLACE: ...> and substitute with your values.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE MEDCORE_DEMO;   -- created in Chapter 2

-- =============================================================================
-- New schemas for Chapter 3 (RAW + STAGING)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
USE SCHEMA RAW;


-- ============================================================================
-- Section 1.2: File Sizing — The 100-250MB Rule
-- ============================================================================

-- Target: 100-250MB compressed files
-- Use the SPLIT option when staging files, or configure your
-- upstream pipeline to produce appropriately sized files

-- COPY INTO raw_encounters
-- FROM @medcore_staging/encounters/
--     FILE_FORMAT = (TYPE = PARQUET)
--     MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;


-- ============================================================================
-- Section 1.3: File Format Selection
-- ============================================================================

-- JSON ingestion: load raw, flatten later
CREATE OR REPLACE TABLE raw_fhir_bundles (
    source_file   STRING,
    load_ts       TIMESTAMP_NTZ DEFAULT SYSDATE(),
    raw_payload   VARIANT
);

COPY INTO raw_fhir_bundles (source_file, raw_payload)
FROM (
    SELECT
        METADATA$FILENAME,
        $1
    FROM @medcore_staging/fhir/
)
    FILE_FORMAT = (TYPE = JSON, STRIP_OUTER_ARRAY = TRUE);

-- CSV ingestion: explicit column mapping with error handling
COPY INTO raw_billing_extracts
FROM @medcore_staging/billing/
    FILE_FORMAT = (
        TYPE = CSV,
        SKIP_HEADER = 1,
        FIELD_OPTIONALLY_ENCLOSED_BY = '"',
        NULL_IF = ('', 'NULL', 'N/A'),
        ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    )
    ON_ERROR = CONTINUE;

-- Parquet ingestion: the gold standard
COPY INTO raw_lab_results
FROM @medcore_staging/lab_results/
    FILE_FORMAT = (TYPE = PARQUET)
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;


-- ============================================================================
-- Section 1.5: MATCH_BY_COLUMN_NAME and Schema Flexibility
-- ============================================================================

-- Before: the lab feed arrived as CSV, which maps columns by position; an
-- inserted column corrupted every field after it (the specimen_type incident)
-- COPY INTO raw_lab_results
-- FROM @medcore_staging/lab_results/
--     FILE_FORMAT = (TYPE = CSV, SKIP_HEADER = 1);

-- After: the feed moved to Parquet, which carries field names, and the load
-- matches on those names
-- COPY INTO raw_lab_results
-- FROM @medcore_staging/lab_results/
--     FILE_FORMAT = (TYPE = PARQUET)
--     MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;


-- ============================================================================
-- Section 2.2: AWS S3 Stages
-- ============================================================================

-- Roles: CREATE INTEGRATION is an account-level privilege (ACCOUNTADMIN by
-- default). Stages, network rules, and secrets are schema-level, so SYSADMIN
-- suffices for those when it owns the schema and holds USAGE on the
-- integration. This demo stays on ACCOUNTADMIN because MEDCORE_DEMO is owned
-- by it.
USE ROLE ACCOUNTADMIN;

-- Step 1: Create a Storage Integration
CREATE OR REPLACE STORAGE INTEGRATION medcore_s3_integration
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<REPLACE: aws-account-id>:role/SnowflakeStageRole'
    STORAGE_ALLOWED_LOCATIONS = (
        's3://<REPLACE: your-bucket-name>/raw/',
        's3://<REPLACE: your-bucket-name>/staging/'
    )
    ENABLED = TRUE;

-- Step 2: Retrieve Snowflake's IAM identity and update AWS trust policy
DESCRIBE INTEGRATION medcore_s3_integration;

-- Step 3: Create the External Stage
CREATE OR REPLACE STAGE medcore_s3_stage
    STORAGE_INTEGRATION = medcore_s3_integration
    URL = 's3://<REPLACE: your-bucket-name>/raw/'
    FILE_FORMAT = (TYPE = PARQUET);

-- List files in the stage
LIST @medcore_s3_stage;

-- Load data
-- COPY INTO raw_encounters
-- FROM @medcore_s3_stage/encounters/2026/03/
--     MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;


-- ============================================================================
-- Section 2.3: Azure Blob Storage Stages
-- (Azure only — included for reference, not testable on AWS accounts)
-- ============================================================================

-- CREATE OR REPLACE STORAGE INTEGRATION medcore_azure_integration
--     TYPE = EXTERNAL_STAGE
--     STORAGE_PROVIDER = 'AZURE'
--     AZURE_TENANT_ID = '<your-azure-tenant-id>'
--     STORAGE_ALLOWED_LOCATIONS = (
--         'azure://medcoreingest.blob.core.windows.net/raw/',
--         'azure://medcoreingest.blob.core.windows.net/staging/'
--     )
--     ENABLED = TRUE;
--
-- CREATE OR REPLACE STAGE medcore_azure_stage
--     STORAGE_INTEGRATION = medcore_azure_integration
--     URL = 'azure://medcoreingest.blob.core.windows.net/raw/'
--     FILE_FORMAT = (TYPE = PARQUET);


-- ============================================================================
-- Section 2.4: Google Cloud Storage Stages
-- (GCS only — included for reference)
-- ============================================================================

-- CREATE OR REPLACE STORAGE INTEGRATION medcore_gcs_integration
--     TYPE = EXTERNAL_STAGE
--     STORAGE_PROVIDER = 'GCS'
--     STORAGE_ALLOWED_LOCATIONS = (
--         'gcs://medcore-ingest-prod/raw/',
--         'gcs://medcore-ingest-prod/staging/'
--     )
--     ENABLED = TRUE;
--
-- CREATE OR REPLACE STAGE medcore_gcs_stage
--     STORAGE_INTEGRATION = medcore_gcs_integration
--     URL = 'gcs://medcore-ingest-prod/raw/'
--     FILE_FORMAT = (TYPE = PARQUET);


-- ============================================================================
-- Section 2.5: Stage Organization Patterns
-- ============================================================================

-- Pattern 1: One Stage Per Source System
-- CREATE STAGE stage_ehr_exports     URL = '...blob.../ehr/';
-- CREATE STAGE stage_lab_results     URL = '...blob.../lab/';
-- CREATE STAGE stage_billing_feeds   URL = '...blob.../billing/';

-- Pattern 2: One Stage Per Ingestion Layer
-- CREATE STAGE stage_raw_landing     URL = '...blob.../raw/';
-- CREATE STAGE stage_quarantine      URL = '...blob.../quarantine/';
-- CREATE STAGE stage_archive         URL = '...blob.../archive/';


-- ============================================================================
-- Section 2.6: Directory Tables for File-Driven Ingestion
-- ============================================================================

-- ALTER STAGE medcore_s3_stage SET DIRECTORY = (ENABLE = TRUE);
-- ALTER STAGE medcore_s3_stage REFRESH;

-- Query available files
-- SELECT
--     RELATIVE_PATH,
--     SIZE,
--     LAST_MODIFIED,
--     MD5
-- FROM DIRECTORY(@medcore_s3_stage)
-- WHERE LAST_MODIFIED > DATEADD('day', -1, CURRENT_TIMESTAMP())
-- ORDER BY LAST_MODIFIED DESC;


-- ============================================================================
-- Section 3.2: Fivetran — querying Fivetran-landed data (reference only)
-- ============================================================================

-- SELECT
--     w.employee_id,
--     w.full_name,
--     w.department,
--     w.hire_date
-- FROM medcore_raw.workday.worker w
-- WHERE w._fivetran_synced > DATEADD('hour', -24, CURRENT_TIMESTAMP());


-- ============================================================================
-- Section 4.1: Orchestration Procedures — Managing Multi-Step Loads
-- ============================================================================

-- Logging table for all ingestion runs
-- SYSDATE() records UTC; CURRENT_TIMESTAMP() would record the session time zone
CREATE TABLE IF NOT EXISTS ingestion_log (
    batch_date        DATE,
    source            STRING,
    status            STRING,
    rows_loaded       INT,
    duration_seconds  INT,
    logged_at         TIMESTAMP_NTZ DEFAULT SYSDATE()
);

-- Raw tables needed by the orchestration procedure
CREATE TABLE IF NOT EXISTS raw_encounters (
    encounter_id    STRING,
    patient_id      STRING,
    facility_code   STRING,
    encounter_date  DATE,
    diagnosis_code  STRING,
    provider_id     STRING,
    charge_amount   NUMBER(12,2),
    load_ts         TIMESTAMP_NTZ DEFAULT SYSDATE()
);

CREATE TABLE IF NOT EXISTS raw_lab_results (
    lab_id          STRING,
    patient_id      STRING,
    test_code       STRING,
    result_value    STRING,
    result_unit     STRING,
    collected_date  DATE,
    load_ts         TIMESTAMP_NTZ DEFAULT SYSDATE()
);

CREATE TABLE IF NOT EXISTS raw_billing_extracts (
    billing_id      STRING,
    patient_id      STRING,
    facility_code   STRING,
    service_date    DATE,
    cpt_code        STRING,
    charge_amount   NUMBER(12,2),
    payer_code      STRING,
    load_ts         TIMESTAMP_NTZ DEFAULT SYSDATE()
);

-- Orchestration procedure
-- NOTE: COPY INTO cannot take a computed stage path, so each statement is
--       assembled as a string and run with EXECUTE IMMEDIATE. String
--       concatenation itself is fine; a Snowflake Scripting variable used
--       inside an expression takes no colon prefix (the colon is only for
--       binding a variable into a SQL statement).
-- FIX: SQLERRM must be captured into a variable before use in VALUES.
-- FIX: DATEDIFF() cannot be used directly inside VALUES; pre-compute into a variable.
CREATE OR REPLACE PROCEDURE load_daily_batch(batch_date DATE)
RETURNS TABLE (source STRING, status STRING, rows_loaded INT, duration_seconds INT)
LANGUAGE SQL
AS
$$
DECLARE
    results RESULTSET;
    start_ts TIMESTAMP_NTZ;
    row_count INT;
    date_path STRING;
    copy_sql STRING;
    err_msg STRING;
    elapsed INT;
BEGIN
    date_path := TO_CHAR(:batch_date, 'YYYY/MM/DD');

    CREATE OR REPLACE TEMPORARY TABLE _load_results (
        source STRING,
        status STRING,
        rows_loaded INT,
        duration_seconds INT
    );

    -- Load 1: EHR encounters
    start_ts := CURRENT_TIMESTAMP();
    BEGIN
        copy_sql := 'COPY INTO raw_encounters FROM @stage_ehr_exports/encounters/'
                    || date_path || '/ FILE_FORMAT = (TYPE = PARQUET)'
                    || ' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE';
        EXECUTE IMMEDIATE :copy_sql;

        -- COPY INTO returns one row per FILE; SUM(rows_loaded) totals the rows
        SELECT SUM(rows_loaded) INTO :row_count
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        elapsed := DATEDIFF('second', :start_ts, CURRENT_TIMESTAMP());
        INSERT INTO _load_results
        VALUES ('ehr_encounters', 'SUCCESS', :row_count, :elapsed);
    EXCEPTION
        WHEN OTHER THEN
            err_msg := SQLERRM;
            elapsed := DATEDIFF('second', :start_ts, CURRENT_TIMESTAMP());
            INSERT INTO _load_results
            VALUES ('ehr_encounters', 'FAILED: ' || :err_msg, 0, :elapsed);
    END;

    -- Load 2: Lab results
    start_ts := CURRENT_TIMESTAMP();
    BEGIN
        copy_sql := 'COPY INTO raw_lab_results FROM @stage_lab_results/results/'
                    || date_path || '/ FILE_FORMAT = (TYPE = PARQUET)'
                    || ' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE';
        EXECUTE IMMEDIATE :copy_sql;

        -- COPY INTO returns one row per FILE; SUM(rows_loaded) totals the rows
        SELECT SUM(rows_loaded) INTO :row_count
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        elapsed := DATEDIFF('second', :start_ts, CURRENT_TIMESTAMP());
        INSERT INTO _load_results
        VALUES ('lab_results', 'SUCCESS', :row_count, :elapsed);
    EXCEPTION
        WHEN OTHER THEN
            err_msg := SQLERRM;
            elapsed := DATEDIFF('second', :start_ts, CURRENT_TIMESTAMP());
            INSERT INTO _load_results
            VALUES ('lab_results', 'FAILED: ' || :err_msg, 0, :elapsed);
    END;

    -- Load 3: Billing extracts
    start_ts := CURRENT_TIMESTAMP();
    BEGIN
        copy_sql := 'COPY INTO raw_billing_extracts FROM @stage_billing_feeds/billing/'
                    || date_path || '/ FILE_FORMAT = (TYPE = CSV, SKIP_HEADER = 1,'
                    || ' FIELD_OPTIONALLY_ENCLOSED_BY = ''"'','
                    || ' NULL_IF = ('''', ''NULL'', ''N/A''))'
                    || ' ON_ERROR = CONTINUE';
        EXECUTE IMMEDIATE :copy_sql;

        -- COPY INTO returns one row per FILE; SUM(rows_loaded) totals the rows
        SELECT SUM(rows_loaded) INTO :row_count
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        elapsed := DATEDIFF('second', :start_ts, CURRENT_TIMESTAMP());
        INSERT INTO _load_results
        VALUES ('billing_extracts', 'SUCCESS', :row_count, :elapsed);
    EXCEPTION
        WHEN OTHER THEN
            err_msg := SQLERRM;
            elapsed := DATEDIFF('second', :start_ts, CURRENT_TIMESTAMP());
            INSERT INTO _load_results
            VALUES ('billing_extracts', 'FAILED: ' || :err_msg, 0, :elapsed);
    END;

    -- Log results to persistent table
    INSERT INTO ingestion_log (batch_date, source, status, rows_loaded,
                               duration_seconds, logged_at)
    SELECT :batch_date, source, status, rows_loaded,
           duration_seconds, SYSDATE()
    FROM _load_results;

    results := (SELECT * FROM _load_results);
    RETURN TABLE(results);
END;
$$;

-- Run the daily batch
-- CALL load_daily_batch('2026-03-07');

-- Schedule the batch (book Section 4.1, step 6). Tasks do NOT retry on their
-- own: TASK_AUTO_RETRY_ATTEMPTS (default 0) enables graph-level retry on a
-- root task. The master task in Section 4.4 supersedes this one; resume only
-- one of the two.
-- NOTE: the book shows WAREHOUSE = INGESTION_WH; this repo standardizes on
--       BOOK_WH created by setup/snowflake_setup.sql.
CREATE OR REPLACE TASK load_daily_batch_task
    WAREHOUSE = BOOK_WH
    SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
    CALL load_daily_batch(CURRENT_DATE() - 1);
-- ALTER TASK load_daily_batch_task RESUME;

-- Check load history
-- SELECT * FROM ingestion_log
-- WHERE batch_date = '2026-03-07'
-- ORDER BY logged_at;


-- ============================================================================
-- Section 4.2: API-Calling Procedures — Snowflake as an Ingestion Engine
-- ============================================================================

-- Step 1: Create the External Access Integration
-- NOTE: External access integrations are NOT supported on trial accounts.
--       Network rule and secret will create successfully, but the integration
--       and Python procedure below require a paid Snowflake account.

USE ROLE ACCOUNTADMIN;   -- external access integrations are account-level

CREATE OR REPLACE NETWORK RULE pharmacy_api_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('api.medcore-pharmacy.com:443');

CREATE OR REPLACE SECRET pharmacy_api_key
    TYPE = GENERIC_STRING
    SECRET_STRING = '<REPLACE: your-api-key>';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION pharmacy_api_access
    ALLOWED_NETWORK_RULES = (pharmacy_api_rule)
    ALLOWED_AUTHENTICATION_SECRETS = (pharmacy_api_key)
    ENABLED = TRUE;

-- Step 2: Build the Ingestion Procedure
CREATE OR REPLACE PROCEDURE ingest_pharmacy_dispensing(batch_date DATE)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (pharmacy_api_access)
SECRETS = ('api_key' = pharmacy_api_key)
AS
$$
import requests
import json
from datetime import datetime

def run(session, batch_date):
    import _snowflake

    api_key = _snowflake.get_generic_secret_string('api_key')
    base_url = 'https://api.medcore-pharmacy.com/v2/dispensing'

    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json'
    }

    all_records = []
    page = 1
    page_size = 1000

    while True:
        params = {
            'date': str(batch_date),
            'page': page,
            'page_size': page_size
        }

        response = requests.get(base_url, headers=headers,
                                params=params, timeout=30)
        response.raise_for_status()

        data = response.json()
        records = data.get('dispensing_records', [])

        if not records:
            break

        all_records.extend(records)
        page += 1

        if page > 500:
            break

    if not all_records:
        return {'status': 'no_data', 'records': 0,
                'batch_date': str(batch_date)}

    df = session.create_dataframe(
        [[json.dumps(r), str(batch_date), datetime.utcnow().isoformat()]
         for r in all_records],
        schema=['raw_payload', 'batch_date', 'ingested_at']
    )

    df.write.mode('append').save_as_table(
        'raw_pharmacy_dispensing'
    )

    return {
        'status': 'success',
        'records': len(all_records),
        'pages': page - 1,
        'batch_date': str(batch_date)
    }
$$;

-- Run the API ingestion
-- CALL ingest_pharmacy_dispensing('2026-03-07');


-- ============================================================================
-- Section 4.3: Managing Incremental State
-- ============================================================================

CREATE TABLE IF NOT EXISTS ingestion_watermarks (
    source_name     STRING PRIMARY KEY,
    last_batch_date DATE,
    last_record_id  STRING,
    last_run_ts     TIMESTAMP_NTZ,
    records_loaded  INT
);

-- Update watermark after successful ingestion (template — use inside procedure)
-- MERGE INTO ingestion_watermarks target
-- USING (
--     SELECT
--         'pharmacy_dispensing' AS source_name,
--         :batch_date AS last_batch_date,
--         :last_record_id AS last_record_id,
--         SYSDATE() AS last_run_ts,
--         :record_count AS records_loaded
-- ) source
--     ON target.source_name = source.source_name
-- WHEN MATCHED THEN UPDATE SET
--     last_batch_date = source.last_batch_date,
--     last_record_id = source.last_record_id,
--     last_run_ts = source.last_run_ts,
--     records_loaded = source.records_loaded
-- WHEN NOT MATCHED THEN INSERT
--     (source_name, last_batch_date, last_record_id,
--      last_run_ts, records_loaded)
--     VALUES (source.source_name, source.last_batch_date,
--             source.last_record_id, source.last_run_ts,
--             source.records_loaded);


-- ============================================================================
-- Section 4.4: Combining Both Patterns — Full Daily Ingestion
-- ============================================================================

-- Detailed logging table
CREATE TABLE IF NOT EXISTS ingestion_log_detailed (
    batch_date  DATE,
    source      STRING,
    status      STRING,
    detail      VARIANT,
    logged_at   TIMESTAMP_NTZ DEFAULT SYSDATE()
);

CREATE OR REPLACE PROCEDURE run_full_daily_ingestion(batch_date DATE)
RETURNS TABLE (source STRING, status STRING, detail VARIANT)
LANGUAGE SQL
AS
$$
DECLARE
    results RESULTSET;
BEGIN
    CREATE OR REPLACE TEMPORARY TABLE _run_results (
        source STRING,
        status STRING,
        detail VARIANT
    );

    -- Phase 1: File-based sources (COPY INTO)
    BEGIN
        CALL load_daily_batch(:batch_date);
        INSERT INTO _run_results
        SELECT source, status, OBJECT_CONSTRUCT('rows_loaded', rows_loaded)
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    EXCEPTION
        WHEN OTHER THEN
            INSERT INTO _run_results
            VALUES ('file_batch', 'FAILED', PARSE_JSON(
                '{"error": "' || SQLERRM || '"}'
            ));
    END;

    -- Phase 2: API sources (external access)
    BEGIN
        LET api_result VARIANT;
        CALL ingest_pharmacy_dispensing(:batch_date);
        SELECT * INTO api_result
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        INSERT INTO _run_results
        VALUES ('pharmacy_api', 'SUCCESS', :api_result);
    EXCEPTION
        WHEN OTHER THEN
            INSERT INTO _run_results
            VALUES ('pharmacy_api', 'FAILED', PARSE_JSON(
                '{"error": "' || SQLERRM || '"}'
            ));
    END;

    -- Log everything
    INSERT INTO ingestion_log_detailed
        (batch_date, source, status, detail, logged_at)
    SELECT :batch_date, source, status, detail, SYSDATE()
    FROM _run_results;

    results := (SELECT * FROM _run_results);
    RETURN TABLE(results);
END;
$$;

-- Schedule the master orchestrator (book Section 4.4, step 6)
CREATE OR REPLACE TASK run_full_daily_ingestion_task
    WAREHOUSE = BOOK_WH
    SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
    CALL run_full_daily_ingestion(CURRENT_DATE() - 1);
-- ALTER TASK run_full_daily_ingestion_task RESUME;


-- ============================================================================
-- Section 5.1: Handling COPY INTO Errors and Validation
-- ============================================================================

-- For production batch loads: SKIP_FILE with a threshold
-- COPY INTO raw_billing_extracts
-- FROM @stage_billing_feeds/billing/2026/03/07/
--     FILE_FORMAT = (
--         TYPE = CSV,
--         SKIP_HEADER = 1,
--         FIELD_OPTIONALLY_ENCLOSED_BY = '"',
--         ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
--     )
--     ON_ERROR = 'SKIP_FILE_10'
--     VALIDATION_MODE = RETURN_ERRORS;


-- ============================================================================
-- Section 5.1 (continued): VALIDATION_MODE — Test Before You Load
-- ============================================================================

-- Return all errors without loading any data
-- COPY INTO raw_encounters
-- FROM @stage_ehr_exports/encounters/2026/03/07/
--     FILE_FORMAT = (TYPE = PARQUET)
--     MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
--     VALIDATION_MODE = RETURN_ERRORS;

-- Return the first 100 rows to verify format mapping
-- COPY INTO raw_encounters
-- FROM @stage_ehr_exports/encounters/2026/03/07/
--     FILE_FORMAT = (TYPE = PARQUET)
--     MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
--     VALIDATION_MODE = RETURN_ROWS
--     RETURN_FAILED_ONLY = FALSE;


-- ============================================================================
-- Section 5.2: Implementing Quarantine Patterns
-- ============================================================================

CREATE TABLE IF NOT EXISTS ingestion_quarantine (
    quarantine_id     STRING DEFAULT UUID_STRING(),
    source_name       STRING,
    source_file       STRING,
    error_message     STRING,
    raw_record        VARIANT,
    quarantined_at    TIMESTAMP_NTZ DEFAULT SYSDATE(),
    reviewed          BOOLEAN DEFAULT FALSE,
    resolution        STRING
);

-- Phase 1: Attempt the load with CONTINUE
-- COPY INTO raw_billing_extracts
-- FROM @stage_billing_feeds/billing/2026/03/07/
--     FILE_FORMAT = (
--         TYPE = CSV,
--         SKIP_HEADER = 1,
--         FIELD_OPTIONALLY_ENCLOSED_BY = '"'
--     )
--     ON_ERROR = CONTINUE;

-- Phase 2: Check for rejected records
-- SELECT
--     FILE_NAME,
--     ERROR_COUNT,
--     ERRORS_SEEN,
--     FIRST_ERROR_MESSAGE,
--     FIRST_ERROR_LINE_NUM,
--     FIRST_ERROR_CHARACTER_POS
-- FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
--     TABLE_NAME => 'raw_billing_extracts',
--     START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
-- ))
-- WHERE ERROR_COUNT > 0;

-- Phase 3: Quarantine the failures
-- INSERT INTO ingestion_quarantine (source_name, source_file,
--     error_message, quarantined_at)
-- SELECT
--     'billing_extracts',
--     FILE_NAME,
--     FIRST_ERROR_MESSAGE,
--     SYSDATE()
-- FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
--     TABLE_NAME => 'raw_billing_extracts',
--     START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
-- ))
-- WHERE ERROR_COUNT > 0;


-- ============================================================================
-- Section 5.3: Designing Retry Logic with Idempotency
-- ============================================================================

-- Column order matches the Python procedure's dataframe (append is positional).
-- CLUSTER BY batch_date keeps the idempotent DELETE a metadata-cheap operation.
CREATE TABLE IF NOT EXISTS raw_pharmacy_dispensing (
    raw_payload   VARIANT,
    batch_date    DATE,
    ingested_at   TIMESTAMP_NTZ
)
CLUSTER BY (batch_date);

CREATE OR REPLACE PROCEDURE idempotent_api_load(batch_date DATE)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    BEGIN TRANSACTION;

    DELETE FROM raw_pharmacy_dispensing
    WHERE batch_date = :batch_date;

    CALL ingest_pharmacy_dispensing(:batch_date);

    COMMIT;
    RETURN 'SUCCESS';
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN 'FAILED: ' || SQLERRM;
END;
$$;


-- ============================================================================
-- Section 5.4: Monitoring and Alerting for Pipeline Health
-- ============================================================================

-- The health check is a SQL table function rather than a procedure: the logic
-- is one read-only SELECT, and a function slots into any query — including the
-- alert condition below, which is a SELECT and cannot CALL a procedure.
-- For range-based anomaly checks (expected min/max rows per table), extend the
-- CASE branches with BETWEEN bounds.
CREATE OR REPLACE FUNCTION check_ingestion_health(check_date DATE)
RETURNS TABLE (source STRING, status STRING, detail STRING)
AS
$$
    SELECT source_name, status, detail FROM (
        SELECT 'ehr_encounters' AS source_name,
            CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE 'MISSING' END AS status,
            COUNT(*)::STRING || ' rows' AS detail
        FROM raw_encounters WHERE load_ts::DATE = check_date
        UNION ALL
        SELECT 'lab_results',
            CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE 'MISSING' END,
            COUNT(*)::STRING || ' rows'
        FROM raw_lab_results WHERE load_ts::DATE = check_date
        UNION ALL
        SELECT 'quarantine',
            CASE WHEN COUNT(*) > 100 THEN 'HIGH' ELSE 'OK' END,
            COUNT(*)::STRING || ' records'
        FROM ingestion_quarantine WHERE quarantined_at::DATE = check_date
    )
$$;

-- Manual check
-- SELECT * FROM TABLE(check_ingestion_health('2026-03-07'));

-- Chain the health check to the ingestion task with AFTER (a child task cannot
-- carry its own SCHEDULE). Each morning's verdict lands in ingestion_log, so
-- the health history sits beside the load history it audits.
CREATE OR REPLACE TASK daily_health_check
    WAREHOUSE = BOOK_WH
    AFTER run_full_daily_ingestion_task
AS
    INSERT INTO ingestion_log (batch_date, source, status, logged_at)
    SELECT CURRENT_DATE() - 1, source, status, SYSDATE()
    FROM TABLE(check_ingestion_health(CURRENT_DATE() - 1));

ALTER TASK daily_health_check RESUME;

-- Email alerting requires a notification integration whose recipients are
-- VERIFIED users in this account; creation fails for unverified addresses.
CREATE OR REPLACE NOTIFICATION INTEGRATION ingestion_alerts
    TYPE = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('<REPLACE: your-verified-email>');

-- Alerts are created suspended; the RESUME below turns evaluation on.
CREATE OR REPLACE ALERT ingestion_health_alert
    WAREHOUSE = BOOK_WH
    SCHEDULE = 'USING CRON 30 7 * * * UTC'
    IF (EXISTS (
        SELECT 1
        FROM TABLE(check_ingestion_health(CURRENT_DATE() - 1))
        WHERE status IN ('MISSING', 'HIGH')))
    THEN CALL SYSTEM$SEND_EMAIL(
        'ingestion_alerts',
        '<REPLACE: your-verified-email>',
        'Ingestion health check failed',
        'One or more sources reported MISSING or HIGH.');

ALTER ALERT ingestion_health_alert RESUME;
