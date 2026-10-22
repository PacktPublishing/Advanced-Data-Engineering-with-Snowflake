-- =====================================================================
-- DCM definitions: silver / cleansed layer
-- =====================================================================
-- Matches the chapter Section 3.3 DEFINE block. The Dynamic Table is the
-- same SELECT from Chapter 9, now managed as code. WAREHOUSE = {{ wh_name }}
-- references the Terraform-owned warehouse by name via the manifest variable;
-- nothing here defines it. The name crosses the tool boundary through the
-- manifest, not Terraform state (DCM cannot read it).
--
-- FROM reads the shared unsuffixed raw layer. env_suffix isolates the
-- silver database: SILVER_DB_DEV in DEV, SILVER_DB in PROD.
-- =====================================================================

DEFINE DATABASE silver_db{{ env_suffix }};

DEFINE SCHEMA silver_db{{ env_suffix }}.transactions;

DEFINE DYNAMIC TABLE silver_db{{ env_suffix }}.transactions.transactions_clean_dt
    TARGET_LAG = 'DOWNSTREAM'
    WAREHOUSE = {{ wh_name }}
    REFRESH_MODE = INCREMENTAL
    AS
    SELECT
        raw_data:transaction_id::STRING                  AS transaction_id,
        UPPER(raw_data:merchant.id::STRING)              AS merchant_id,
        UPPER(raw_data:currency::STRING)                 AS currency,
        TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2)   AS amount,
        TRY_TO_TIMESTAMP_NTZ(raw_data:timestamp::STRING) AS transaction_ts,
        raw_data:status::STRING                          AS status
    FROM raw_db.streaming.raw_transactions;
