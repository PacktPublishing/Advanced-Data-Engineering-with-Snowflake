-- =====================================================================
-- DCM definitions: shared raw / landing layer
-- =====================================================================
-- Both DEV and PROD read the same unsuffixed raw layer (see Section 3.3).
-- DEV builds silver_db_DEV from live input while writing nowhere near PROD
-- tables. Only PROD manages these shared objects; DEV references them.
-- The shared stream stays in native SQL while DEFINE STREAM is preview.
--
-- Warehouse and roles belong to Terraform (infra/), not this project.
-- =====================================================================

{% if env_suffix == '' %}
DEFINE DATABASE raw_db;

DEFINE SCHEMA raw_db.streaming;

DEFINE TABLE raw_db.streaming.raw_transactions (
    raw_data   VARIANT,
    loaded_at  TIMESTAMP_NTZ
);

{% endif %}
