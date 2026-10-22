-- =============================================================================
-- Chapter 4: Real-Time Ingestion and Change Data Capture
-- KAFKA SETUP -- Sections 2.3, 2.4, 3.2, and 4.5 (Kafka connector, streaming
-- mode, error handling / DLQ, performance tuning, Azure Event Hubs).
--
-- Run order for the chapter: this file -> chapter4_openflow_setup.sql ->
-- chapter4_cdc_setup.sql. The three files are independent; run only what the
-- section you are following needs.
--
-- Prerequisites:
--   - setup/snowflake_setup.sql executed (UTIL db, BOOK_WH, role blocks)
--   - Running Kafka cluster with Kafka Connect for the connector labs
--   - Labs tested with Snowflake Kafka Connector 2.4.1 (streaming mode);
--     connector 4.0+ (GA April 2026) runs on the high-performance
--     architecture -- check release notes before adopting
--
-- Placeholders: search for <REPLACE: ...> and substitute with your values.
-- Role convention (per the book): USERADMIN creates roles, SYSADMIN owns
-- databases/schemas/tables and object grants, ACCOUNTADMIN only where an
-- account-level privilege requires it (integrations, account grants).
-- =============================================================================

-- Databases used throughout the chapter. Chapters 2-3 create these already;
-- IF NOT EXISTS makes this chapter runnable standalone. SILVER_DB is the
-- book's standard silver-layer database name and is used as-is in all
-- chapter code (no renaming required).
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS RAW_DB;
CREATE DATABASE IF NOT EXISTS SILVER_DB;
CREATE WAREHOUSE IF NOT EXISTS BOOK_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE BOOK_WH;
USE DATABASE RAW_DB;

-- =============================================================================
-- Section 2.3: Configuring Kafka Connector v2 in Streaming Mode
-- =============================================================================

-- Create schemas for streaming and CDC workloads
CREATE SCHEMA IF NOT EXISTS STREAMING;
CREATE SCHEMA IF NOT EXISTS CDC;
CREATE SCHEMA IF NOT EXISTS LANDING;
USE SCHEMA STREAMING;

-- Create a dedicated role for streaming ingestion (roles are created by
-- USERADMIN per the book's role convention)
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS streaming_ingest_role;

-- Grant required privileges (object grants run as SYSADMIN, which owns RAW_DB)
USE ROLE SYSADMIN;
GRANT USAGE ON DATABASE RAW_DB TO ROLE streaming_ingest_role;
GRANT USAGE ON SCHEMA RAW_DB.STREAMING TO ROLE streaming_ingest_role;
GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA RAW_DB.STREAMING
    TO ROLE streaming_ingest_role;
GRANT CREATE TABLE ON SCHEMA RAW_DB.STREAMING TO ROLE streaming_ingest_role;
GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE streaming_ingest_role;

-- Create the target table for fraud events.
-- The `payload` VARIANT column absorbs every event field; new fields from the
-- source system do not require table schema changes.
CREATE OR REPLACE TABLE RAW_DB.STREAMING.fraud_events (
    event_id STRING,
    transaction_id STRING,
    amount NUMBER(12,2),
    merchant_id STRING,
    event_type STRING,
    risk_score NUMBER(5,2),
    event_timestamp TIMESTAMP_NTZ,
    payload VARIANT,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Generate RSA key pair (run locally in your terminal, not in Snowflake)
-- openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_streaming_key.p8 -nocrypt
-- openssl rsa -in snowflake_streaming_key.p8 -pubout -out snowflake_streaming_key.pub

-- Assign the public key to your Snowflake user
ALTER USER <REPLACE: streaming_ingest_user>
    SET RSA_PUBLIC_KEY='<REPLACE: paste-your-public-key-here>';

-- Kafka Connector v2 Configuration (deploy via Kafka Connect REST API)
-- For Amazon MSK (SASL/IAM), use bootstrap from terraform output and
--   chapters/chapter4/kafka/msk-snowflake-sink-connector.example.json
--   (Connect worker needs aws-msk-iam-auth JAR). See setup/TESTING.md.
-- Run this from your terminal, NOT in Snowflake:
--
-- curl -X POST http://localhost:8083/connectors \
--   -H "Content-Type: application/json" \
--   -d '{
--       "name": "techflow-fraud-streaming",
--       "config": {
--           "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
--           "tasks.max": "4",
--           "topics": "fraud-events",
--           "snowflake.url.name": "<REPLACE: your-account>.snowflakecomputing.com",
--           "snowflake.user.name": "<REPLACE: streaming_ingest_user>",
--           "snowflake.private.key": "${file:/secrets/snowflake_streaming_key.p8}",
--           "snowflake.database.name": "RAW_DB",
--           "snowflake.schema.name": "STREAMING",
--           "snowflake.role.name": "STREAMING_INGEST_ROLE",
--           "snowflake.ingestion.method": "SNOWPIPE_STREAMING",
--           "snowflake.enable.schematization": "true",
--           "buffer.count.records": "10000",
--           "buffer.flush.time": "10",
--           "buffer.size.bytes": "5000000",
--           "key.converter": "org.apache.kafka.connect.storage.StringConverter",
--           "value.converter": "com.snowflake.kafka.connector.records.SnowflakeJsonConverter"
--       }
--   }'

-- Check that data is flowing
SELECT COUNT(*), MIN(_loaded_at), MAX(_loaded_at)
FROM RAW_DB.STREAMING.fraud_events
WHERE _loaded_at > DATEADD(minute, -5, CURRENT_TIMESTAMP());

-- Check channel status
SELECT *
FROM TABLE(INFORMATION_SCHEMA.PIPE_USAGE_HISTORY(
    DATE_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP()),
    DATE_RANGE_END => CURRENT_TIMESTAMP()
));

-- Monitor ingestion latency (difference between event time and load time)
SELECT
    AVG(DATEDIFF(second, event_timestamp, _loaded_at)) AS avg_latency_seconds,
    MAX(DATEDIFF(second, event_timestamp, _loaded_at)) AS max_latency_seconds,
    COUNT(*) AS record_count
FROM RAW_DB.STREAMING.fraud_events
WHERE _loaded_at > DATEADD(hour, -1, CURRENT_TIMESTAMP());



-- =============================================================================
-- Section 2.4: Error Handling for Snowpipe Streaming
-- =============================================================================

-- Dead Letter Queue configuration (add to your Kafka Connector config)
-- Run this from your terminal, NOT in Snowflake:
--
-- curl -X PUT http://localhost:8083/connectors/techflow-fraud-streaming/config \
--   -H "Content-Type: application/json" \
--   -d '{
--       ... (existing config from Section 2.3) ...
--       "errors.tolerance": "all",
--       "errors.deadletterqueue.topic.name": "fraud-events-dlq",
--       "errors.deadletterqueue.topic.replication.factor": "3",
--       "errors.deadletterqueue.context.headers.enable": "true"
--   }'



-- -----------------------------------------------------------------------------
-- DLQ depth alert template (referenced in Section 2.4 of the chapter).
-- DLQ depth lives in Kafka, not Snowflake, so this template assumes a small
-- exporter (scheduled consumer-group check or metrics pipeline) lands the DLQ
-- depth into RAW_DB.STREAMING.kafka_dlq_metrics. Uncomment and adapt.
-- -----------------------------------------------------------------------------
-- CREATE TABLE IF NOT EXISTS RAW_DB.STREAMING.kafka_dlq_metrics (
--     topic STRING, depth NUMBER, _recorded_at TIMESTAMP_NTZ
--         DEFAULT CURRENT_TIMESTAMP()
-- );
--
-- CREATE OR REPLACE ALERT RAW_DB.STREAMING.dlq_depth_alert
--     WAREHOUSE = BOOK_WH
--     SCHEDULE = '60 MINUTE'
--     IF (EXISTS (
--         SELECT 1
--         FROM RAW_DB.STREAMING.kafka_dlq_metrics
--         WHERE topic = 'fraud-events-dlq'
--           AND _recorded_at > DATEADD(hour, -1, CURRENT_TIMESTAMP())
--         HAVING MAX(depth) > 10 * AVG(depth)
--     ))
--     THEN CALL SYSTEM$SEND_EMAIL(
--         'data_ops', 'ops@techflow.com',  -- <REPLACE: your ops email>
--         'DLQ depth alert', 'fraud-events-dlq depth exceeded 10x baseline');
-- ALTER ALERT RAW_DB.STREAMING.dlq_depth_alert RESUME;


-- =============================================================================
-- Section 3.2: Performance Tuning
-- =============================================================================

-- High-throughput Kafka Connector tuning (adjust in connector config)
-- Run this from your terminal, NOT in Snowflake:
--
-- curl -X PUT http://localhost:8083/connectors/techflow-fraud-streaming/config \
--   -H "Content-Type: application/json" \
--   -d '{
--       ... (existing config) ...
--       "tasks.max": "6",
--       "buffer.count.records": "50000",
--       "buffer.flush.time": "30",
--       "buffer.size.bytes": "50000000"
--   }'



-- =============================================================================
-- Section 4.5: Azure Event Hubs via Kafka Connect
-- =============================================================================
-- Prerequisites:
--   - Azure Event Hubs namespace + hub (deploy with setup/terraform/azure/)
--   - Kafka Connect running (use kafka/docker-compose.yml)
--   - Event Hubs connection string from Terraform:
--       cd setup/terraform/azure && terraform output -raw eventhub_connection_string
--
-- Key differences from vanilla Kafka:
--   - Port 9093 (TLS), NOT 9092
--   - SASL_SSL required on all connections (broker, producer, consumer)
--   - Only gzip compression supported
--   - metadata.max.age.ms must be < 240000 (Azure closes idle connections at 240s)

-- Reuses the existing fraud_events table and streaming_ingest_role from Section 2.3.

-- Deploy the Snowflake Kafka Connector pointing at Event Hubs.
-- Run this from your terminal, NOT in Snowflake:
--
-- curl -X POST http://localhost:8083/connectors \
--   -H "Content-Type: application/json" \
--   -d '{
--       "name": "techflow-fraud-eventhubs",
--       "config": {
--           "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
--           "tasks.max": "2",
--           "topics": "fraud-events",
--           "snowflake.url.name": "<REPLACE: your-account>.snowflakecomputing.com",
--           "snowflake.user.name": "<REPLACE: streaming_ingest_user>",
--           "snowflake.private.key": "${file:/secrets/snowflake_streaming_key.p8}",
--           "snowflake.database.name": "RAW_DB",
--           "snowflake.schema.name": "STREAMING",
--           "snowflake.role.name": "STREAMING_INGEST_ROLE",
--           "snowflake.ingestion.method": "SNOWPIPE_STREAMING",
--           "snowflake.enable.schematization": "true",
--           "buffer.count.records": "10000",
--           "buffer.flush.time": "10",
--           "buffer.size.bytes": "5000000",
--           "key.converter": "org.apache.kafka.connect.storage.StringConverter",
--           "value.converter": "com.snowflake.kafka.connector.records.SnowflakeJsonConverter",
--
--           "consumer.override.bootstrap.servers": "<REPLACE: namespace>.servicebus.windows.net:9093",
--           "consumer.override.security.protocol": "SASL_SSL",
--           "consumer.override.sasl.mechanism": "PLAIN",
--           "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$ConnectionString\" password=\"<REPLACE: connection-string>\";",
--           "consumer.override.metadata.max.age.ms": "180000"
--       }
--   }'
--
-- NOTE: The Kafka Connect worker itself also needs SASL_SSL config in its
-- connect-distributed.properties if the worker connects to Event Hubs directly
-- (rather than a local Kafka broker). See kafka/README.md for details.

-- Verify data flow (same queries as Section 2.3)
SELECT COUNT(*), MIN(_loaded_at), MAX(_loaded_at)
FROM RAW_DB.STREAMING.fraud_events
WHERE _loaded_at > DATEADD(minute, -5, CURRENT_TIMESTAMP());

