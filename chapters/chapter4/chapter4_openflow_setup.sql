-- =============================================================================
-- Chapter 4: Real-Time Ingestion and Change Data Capture
-- OPENFLOW SETUP -- Section 4 (Building Visual Integration Pipelines).
--
-- OpenFlow gen 2. Snowflake retired gen 1 deployment creation on 2026-09-09;
-- every new deployment is gen 2, and deployments and runtimes are SQL objects
-- (CREATE OPENFLOW DEPLOYMENT / CREATE OPENFLOW RUNTIME). Written against the
-- gen 2 GA documentation, October 2026.
--
-- Independent of chapter4_kafka_setup.sql and chapter4_cdc_setup.sql; run the
-- blocks below in order. Blocks match the chapter's references:
--   BLOCK 1  admin role and OAuth        (Preparing the admin role and OAuth)
--   BLOCK 2  egress, tables, grants      (Setting up network rules, egress, and grants)
--   BLOCK 3  deployment                  (Creating the deployment and runtime, step 1)
--   BLOCK 4  runtime                     (Creating the deployment and runtime, step 2)
--   BLOCK 5  canvas walkthrough + cost   (Building the processor chain; step 2b = Jolt spec;
--                                         Scheduling, testing, and monitoring)
--   BLOCK 6  Kafka sources on the canvas (Extending OpenFlow to Kafka Sources)
--   BLOCK 7  Kinesis connector           (bonus, not in the chapter text)
-- Teardown lives in chapter4_openflow_teardown.sql so running this file end to
-- end never removes what it just built.
--
-- Prerequisites:
--   - Paid Snowflake account with OpenFlow enabled (trial accounts need the
--     Snowflake account team to enable it)
--   - Room for one more OpenFlow Snowflake deployment: an account holds at most
--     three, gen 1 and gen 2 combined (check with SHOW OPENFLOW DEPLOYMENTS and
--     SHOW OPENFLOW DATA PLANE INTEGRATIONS)
--   - ORGADMIN accepted the Openflow terms of service once per org
--     (Snowsight, as ORGADMIN: Admin » Terms » Openflow terms of service » Accept)
--   - Flows themselves are built on the Snowsight canvas -- SQL here prepares
--     egress, secrets, tables, grants, the deployment, and the runtime
--
-- Placeholders: search for <REPLACE: ...> and substitute with your values.
-- Role convention (per the book): USERADMIN creates roles, SYSADMIN owns
-- databases/schemas/tables and object grants, ACCOUNTADMIN only where an
-- account-level privilege requires it (integrations, account grants).
-- OpenFlow objects (OPENFLOW_DB, the deployment, the runtime) are owned by
-- OPENFLOW_ADMIN. Do not transfer ownership of gen 2 OpenFlow objects:
-- Snowflake documents that GRANT OWNERSHIP on them can break functionality.
-- =============================================================================

USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS RAW_DB;
CREATE SCHEMA IF NOT EXISTS RAW_DB.STREAMING;
USE WAREHOUSE BOOK_WH;

-- =============================================================================
-- BLOCK 1 — ADMIN ROLE AND OAUTH (run first; referenced in the chapter as
-- "the admin role and OAuth block")
-- =============================================================================
-- Openflow login (Launch Openflow) is blocked when your Snowflake DEFAULT ROLE
-- is ACCOUNTADMIN, ORGADMIN, GLOBALORGADMIN, or SECURITYADMIN. Create
-- OPENFLOW_ADMIN, grant the gen 2 account privileges, then grant that role to
-- your user and (optionally) SYSADMIN. Set DEFAULT_ROLE to OPENFLOW_ADMIN and
-- enable secondary roles so other privileges stay available during the session.
--
-- The block also creates OPENFLOW_DB.CONTROL, the infrastructure ("control")
-- schema that holds gen 2 runtimes and connectors. Snowflake recommends keeping
-- it apart from the databases flows write to, so RAW_DB stays the landing DB.
--
-- Reference: https://docs.snowflake.com/en/user-guide/data-integration/openflow/setup-openflow-spcs-sf
-- =============================================================================

USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS OPENFLOW_ADMIN;

-- Account-level privileges need ACCOUNTADMIN
USE ROLE ACCOUNTADMIN;

GRANT CREATE ROLE ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE OPENFLOW DEPLOYMENT ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;

-- Snowflake deployments run on SPCS compute pools:
GRANT CREATE COMPUTE POOL ON ACCOUNT TO ROLE OPENFLOW_ADMIN;

-- Let SYSADMIN inherit Openflow admin for break-glass / power users
GRANT ROLE OPENFLOW_ADMIN TO ROLE SYSADMIN;

-- Grant to each human who will click "Launch Openflow" (repeat per user)
GRANT ROLE OPENFLOW_ADMIN TO USER <REPLACE: your_snowflake_username>;

-- Required for Openflow login: default role cannot be ACCOUNTADMIN (etc.)
ALTER USER <REPLACE: your_snowflake_username> SET DEFAULT_ROLE = OPENFLOW_ADMIN;

-- Recommended: keep other granted roles active for worksheets and objects
ALTER USER <REPLACE: your_snowflake_username> SET DEFAULT_SECONDARY_ROLES = ('ALL');

-- Infrastructure database and schema for gen 2 runtimes and connectors
USE ROLE OPENFLOW_ADMIN;
CREATE DATABASE IF NOT EXISTS OPENFLOW_DB;
CREATE SCHEMA IF NOT EXISTS OPENFLOW_DB.CONTROL;

USE ROLE ACCOUNTADMIN;
GRANT CREATE OPENFLOW RUNTIME ON SCHEMA OPENFLOW_DB.CONTROL TO ROLE OPENFLOW_ADMIN;
GRANT CREATE OPENFLOW CONNECTOR ON SCHEMA OPENFLOW_DB.CONTROL TO ROLE OPENFLOW_ADMIN;

-- Existing gen 1 deployment only (cannot create new gen 1 deployments): to add
-- a gen 1 runtime to it you would also need
--   GRANT CREATE OPENFLOW RUNTIME INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;



-- =============================================================================
-- BLOCK 2 — EGRESS, TABLES, SECRET, AND GRANTS (referenced in the chapter as
-- "the egress and grants block"; SQL prerequisites only)
-- =============================================================================
-- Snowflake has never shipped CREATE PIPELINE / ALTER PIPELINE / EXECUTE
-- PIPELINE / SHOW PIPELINES for OpenFlow. CREATE PIPE is Snowpipe (file-based
-- loads), a different object type entirely.
--
-- IMPORTANT: network rules and external access integrations use
-- CREATE ... IF NOT EXISTS. CREATE OR REPLACE on either object silently
-- detaches it from every OpenFlow runtime that references it. To change the
-- rule set later, use:
--   ALTER EXTERNAL ACCESS INTEGRATION partner_api_access
--     SET ALLOWED_NETWORK_RULES = (<every existing rule>, <new rule>);
--
-- Prerequisites:
--   - Enterprise+ paid account; External Access Integrations are not
--     available on trial.
--   - ACCOUNTADMIN for integrations; a dedicated execute-as role for the
--     OpenFlow runtime (openflow_runtime_role below).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE RAW_DB;
USE SCHEMA STREAMING;

-- Target table for partner REST payloads (TechFlow narrative)
CREATE OR REPLACE TABLE RAW_DB.STREAMING.partner_transactions (
    transaction_id    STRING,
    amount            NUMBER(12,2),
    merchant_id       STRING,
    status            STRING,
    merchant_name     STRING,
    merchant_category STRING,
    event_timestamp   TIMESTAMP_NTZ,
    payload           VARIANT,
    _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Lab target for Alpha Vantage FX_DAILY API (free tier: 25 requests/day).
-- Returns ~100 daily OHLC exchange rates for a currency pair (e.g. USD → EUR).
-- IMPORTANT: No DEFAULT values on any column — PutSnowpipeStreaming does NOT
-- support columns with DEFAULT, AUTOINCREMENT, IDENTITY, GEO, or collation.
CREATE OR REPLACE TABLE RAW_DB.STREAMING.fx_daily_rates (
    trade_date    DATE,
    from_currency STRING,
    to_currency   STRING,
    open_rate     NUMBER(12,6),
    high_rate     NUMBER(12,6),
    low_rate      NUMBER(12,6),
    close_rate    NUMBER(12,6),
    _loaded_at    TIMESTAMP_NTZ
);

-- Egress: Alpha Vantage FX data API
CREATE NETWORK RULE IF NOT EXISTS RAW_DB.STREAMING.alphavantage_network_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('www.alphavantage.co:443');

-- Egress: fictional TechFlow partner API from the book narrative — replace host with
-- your real partner hostname before calling that API from the canvas.
CREATE NETWORK RULE IF NOT EXISTS RAW_DB.STREAMING.partner_api_network_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('api.partner-network.com:443');

-- One external access integration listing every host the runtime may call.
-- The runtime binds it in BLOCK 4 (EXTERNAL_ACCESS_INTEGRATIONS parameter).
CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS partner_api_access
    ALLOWED_NETWORK_RULES = (
        RAW_DB.STREAMING.alphavantage_network_rule,
        RAW_DB.STREAMING.partner_api_network_rule
    )
    ENABLED = TRUE;

-- API key for Alpha Vantage (free tier). Sign up at https://www.alphavantage.co/support/
-- then set your real key with:
--   ALTER SECRET RAW_DB.STREAMING.partner_api_key SET SECRET_STRING = '<key>';
CREATE SECRET IF NOT EXISTS RAW_DB.STREAMING.partner_api_key
    TYPE = GENERIC_STRING
    SECRET_STRING = '<REPLACE: your_alphavantage_api_key>';

-- Execute-as role: the runtime runs every flow as this role (BLOCK 4,
-- EXECUTE_AS_ROLE). The UI may show it as OPENFLOW_RUNTIME_ROLE.
CREATE ROLE IF NOT EXISTS openflow_runtime_role;
GRANT ROLE openflow_runtime_role TO ROLE OPENFLOW_ADMIN;

-- A gen 2 runtime has no warehouse setting; the flow uses BOOK_WH through
-- these grants on the execute-as role.
GRANT USAGE, OPERATE ON WAREHOUSE BOOK_WH TO ROLE openflow_runtime_role;
GRANT USAGE ON DATABASE RAW_DB TO ROLE openflow_runtime_role;
GRANT USAGE ON SCHEMA RAW_DB.STREAMING TO ROLE openflow_runtime_role;
GRANT INSERT, SELECT ON TABLE RAW_DB.STREAMING.partner_transactions TO ROLE openflow_runtime_role;
GRANT INSERT, SELECT ON TABLE RAW_DB.STREAMING.fx_daily_rates TO ROLE openflow_runtime_role;
GRANT USAGE ON INTEGRATION partner_api_access TO ROLE openflow_runtime_role;
GRANT READ ON SECRET RAW_DB.STREAMING.partner_api_key TO ROLE openflow_runtime_role;

-- The execute-as role also needs USAGE on the runtime's own database and schema
GRANT USAGE ON DATABASE OPENFLOW_DB TO ROLE openflow_runtime_role;
GRANT USAGE ON SCHEMA OPENFLOW_DB.CONTROL TO ROLE openflow_runtime_role;

-- Verify (chapter step 2):
SHOW GRANTS TO ROLE openflow_runtime_role;



-- =============================================================================
-- BLOCK 3 — DEPLOYMENT (referenced in the chapter as "the deployment block")
-- =============================================================================
-- CREATE OPENFLOW DEPLOYMENT returns immediately; provisioning runs in the
-- background (typically 5-10 minutes for a Snowflake deployment). The wait
-- function returns 'OK' once the deployment is ACTIVE. If it times out, the
-- operation keeps running: re-run the wait, do NOT re-issue the CREATE.
--
-- Cost note: the deployment's management compute pool (*_CONTROL_POOL, one
-- CPU_X64_S instance) bills for as long as the deployment exists, even with no
-- runtime running. Remove it with chapter4_openflow_teardown.sql when done.
--
-- If CREATE fails on the deployment limit, the account already has three
-- Snowflake deployments (gen 1 + gen 2). Reuse one by name in BLOCK 4.
--
-- Docs: https://docs.snowflake.com/en/sql-reference/sql/create-openflow-deployment
-- =============================================================================

USE ROLE OPENFLOW_ADMIN;

CREATE OPENFLOW DEPLOYMENT IF NOT EXISTS techflow_ingest
  DEPLOYMENT_TYPE = SNOWFLAKE;

SELECT SYSTEM$WAIT_FOR_STABLE_OPENFLOW_DEPLOYMENTS(900, 'techflow_ingest');
SHOW OPENFLOW DEPLOYMENTS LIKE 'techflow_ingest';
DESCRIBE OPENFLOW DEPLOYMENT techflow_ingest;

-- Optional: send OpenFlow logs and metrics to a dedicated event table
-- (default is the account event table, SNOWFLAKE.TELEMETRY.EVENTS):
-- CREATE EVENT TABLE IF NOT EXISTS OPENFLOW_DB.CONTROL.openflow_events;
-- ALTER OPENFLOW DEPLOYMENT techflow_ingest
--   SET EVENT_TABLE = 'OPENFLOW_DB.CONTROL.openflow_events';
-- SHOW PARAMETERS LIKE 'EVENT_TABLE' IN OPENFLOW DEPLOYMENT techflow_ingest;

-- Optional: share the deployment with other roles. USAGE on a deployment
-- lets a role create runtimes in it; it does NOT grant access to existing
-- runtimes (see BLOCK 4 for runtime grants).
-- GRANT USAGE ON OPENFLOW DEPLOYMENT techflow_ingest TO ROLE <REPLACE: role>;
-- GRANT MONITOR ON OPENFLOW DEPLOYMENT techflow_ingest TO ROLE <REPLACE: role>;



-- =============================================================================
-- BLOCK 4 — RUNTIME (referenced in the chapter as "the runtime block")
-- =============================================================================
-- A gen 2 runtime is a schema-level object in OPENFLOW_DB.CONTROL. Creating
-- it needs USAGE on the database, CREATE OPENFLOW RUNTIME on the schema, and
-- USAGE on the deployment -- OPENFLOW_ADMIN has all three after BLOCKS 1 and 3.
--
--   NODE_TYPE = SMALL   default tier S1 (1 CPU, 4 GB heap), enough for the
--                       four-processor lab. NODE_TYPE cannot change later;
--                       resize within it with SET NODE_TYPE_TIER = 'S2'/'S3'.
--   MIN/MAX_NODES = 1   MAX_NODES caps scale-out and therefore peak cost.
--   EXECUTE_AS_ROLE     role the processors use to read/write Snowflake.
--   EXTERNAL_ACCESS_INTEGRATIONS  egress allowlist from BLOCK 2 (Snowflake
--                       deployments only). Change later with
--                       ALTER OPENFLOW RUNTIME ... ADD | REMOVE EXTERNAL_ACCESS_INTEGRATIONS.
--
-- Provisioning typically takes 3-5 minutes.
-- Docs: https://docs.snowflake.com/en/sql-reference/sql/create-openflow-runtime
-- =============================================================================

USE ROLE OPENFLOW_ADMIN;
USE SCHEMA OPENFLOW_DB.CONTROL;

CREATE OPENFLOW RUNTIME IF NOT EXISTS partner_api_runtime
  IN DEPLOYMENT techflow_ingest
  NODE_TYPE = SMALL
  MIN_NODES = 1
  MAX_NODES = 1
  EXECUTE_AS_ROLE = openflow_runtime_role
  EXTERNAL_ACCESS_INTEGRATIONS = (partner_api_access);

SELECT SYSTEM$WAIT_FOR_STABLE_OPENFLOW_RUNTIMES(600, 'OPENFLOW_DB.CONTROL.PARTNER_API_RUNTIME');
SHOW OPENFLOW RUNTIMES IN SCHEMA OPENFLOW_DB.CONTROL;
DESCRIBE OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime;

-- Optional: let another role use, operate, or watch this runtime. Gen 2 needs
-- the privilege on the runtime itself plus USAGE on its database and schema.
-- GRANT USAGE ON DATABASE OPENFLOW_DB TO ROLE <REPLACE: role>;
-- GRANT USAGE ON SCHEMA OPENFLOW_DB.CONTROL TO ROLE <REPLACE: role>;
-- GRANT OPERATE ON OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime TO ROLE <REPLACE: role>;
-- GRANT MONITOR ON OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime TO ROLE <REPLACE: role>;

-- Cost control between lab sessions (OPERATE privilege). SUSPEND scales the
-- runtime's compute pool to zero nodes; a Snowflake Task can run these on a
-- schedule (Chapter 9 pattern).
-- ALTER OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime SUSPEND;
-- ALTER OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime RESUME;



-- =============================================================================
-- BLOCK 5 — CANVAS WALKTHROUGH + MONITORING (comments plus the cost query;
-- the chapter cites "the canvas walkthrough block", and step 2b below is the
-- full Jolt spec). Only runnable SQL is left uncommented in the companion
-- scripts; UI-only steps live as comments so each file executes end to end.
-- =============================================================================
-- Snowsight UI (no SQL for flow wiring): Ingestion » Openflow » Launch Openflow
-- » Runtimes tab » PARTNER_API_RUNTIME opens the NiFi canvas.
--
-- 1) Import or build the flow. The ready-made flow definition is
--    rest-api-ingestion.json in this folder (drag a Process Group onto the
--    canvas and browse to the file), or wire it by hand as below.
--
-- 2) **Reference canvas — Alpha Vantage FX_DAILY lab** (processors confirmed in
--    OpenFlow NiFi builds as of early 2026; names must match your palette):
--
--    a) **InvokeHTTP** — GET
--       https://www.alphavantage.co/query?function=FX_DAILY&from_symbol=USD&to_symbol=EUR&apikey=<YOUR_KEY>
--       Timer-driven (e.g. 300 sec — free tier allows 25 requests/day).
--       Auto-terminate Original / Retry / No Retry; wire Response → JoltTransformJSON.
--
--    b) **JoltTransformJSON** — DSL = Chain (internal value: jolt-transform-chain).
--       Three-operation spec: (1) shift to restructure the nested date-keyed object
--       into a flat rates[] array with clean column names + extract currency codes
--       from Meta Data; (2) modify-default to fan currency codes into each rate
--       element; (3) remove to strip top-level currency fields.
--       Jolt Specification:
--       [
--         {
--           "operation": "shift",
--           "spec": {
--             "Time Series FX (Daily)": {
--               "*": {
--                 "$": "rates[#2].trade_date",
--                 "1. open": "rates[#2].open_rate",
--                 "2. high": "rates[#2].high_rate",
--                 "3. low": "rates[#2].low_rate",
--                 "4. close": "rates[#2].close_rate"
--               }
--             },
--             "Meta Data": {
--               "2. From Symbol": "from_currency",
--               "3. To Symbol": "to_currency"
--             }
--           }
--         },
--         {
--           "operation": "modify-default",
--           "spec": {
--             "from_currency": "USD",
--             "to_currency": "EUR",
--             "rates": {
--               "*": {
--                 "from_currency": "=(@(3,from_currency))",
--                 "to_currency": "=(@(3,to_currency))"
--               }
--             }
--           }
--         },
--         {
--           "operation": "remove",
--           "spec": {
--             "from_currency": "",
--             "to_currency": ""
--           }
--         }
--       ]
--
--    c) **SplitJson** — JsonPath Expression `$.rates[*]` (one FlowFile per daily
--       rate record; ~100 records per API response). Wire split → PutSnowpipeStreaming.
--
--    d) **PutSnowpipeStreaming** — Authentication Strategy: SNOWFLAKE_SESSION_TOKEN
--       (automatic in SPCS/OpenFlow). Database: RAW_DB, Schema: STREAMING,
--       Table: FX_DAILY_RATES, Role: OPENFLOW_RUNTIME_ROLE (the runtime's
--       execute-as role). Record Reader: JsonTreeReader (enable that controller
--       service). Connection Strategy: STANDARD. Delivery Guarantee: At least once.
--       Client Lag: 1 sec.
--       (PublishSnowpipeStreaming is the high-performance Snowpipe Streaming
--       processor; it expects NDJSON input, so the lab keeps PutSnowpipeStreaming.)
--
--    Each successful GET returns ~100 daily OHLC rates; APPEND inserts duplicate
--    rows on every timer fire — stop the flow or increase interval after you verify
--    the lab.
--
-- 3) **TechFlow partner flow** — same pattern: InvokeHTTP to your partner URL, parse
--    JSON, optional filter, sink to PARTNER_TRANSACTIONS (APPEND/MERGE as designed).
--
-- 4) Scheduling is always on the canvas (timer-driven / triggers) — never SQL CRON.
-- Full narrative: Chapter 4, section "Building a REST API Flow".
-- Cortex batch prompt: .coco-prompts/chapter4-openflow-nifi-workflow.txt
-- ---------------------------------------------------------------------------

-- List gen 2 OpenFlow objects you can see
SHOW OPENFLOW DEPLOYMENTS;
SHOW OPENFLOW RUNTIMES IN ACCOUNT;

-- OpenFlow Snowflake-deployment credits. OPENFLOW_USAGE_HISTORY covers BYOC
-- deployments only, so it is empty for this lab. NAME is the compute pool:
-- *_CONTROL_POOL = deployment management services, *_SMALL/_MEDIUM/_LARGE =
-- runtimes (shared per size within a deployment). Latency up to ~3 hours.
SELECT
  start_time,
  name AS compute_pool,
  credits_used_compute
FROM snowflake.account_usage.metering_history
WHERE service_type = 'OPENFLOW_COMPUTE_SNOWFLAKE'
  AND start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;

-- After the canvas flow runs (Alpha Vantage FX_DAILY lab):
-- SELECT COUNT(*) AS rows_loaded, MIN(trade_date) AS earliest, MAX(trade_date) AS latest
--   FROM RAW_DB.STREAMING.fx_daily_rates;
-- SELECT * FROM RAW_DB.STREAMING.fx_daily_rates ORDER BY trade_date DESC LIMIT 5;
-- After partner flow:
-- SELECT COUNT(*), MAX(_loaded_at) FROM RAW_DB.STREAMING.partner_transactions;



-- =============================================================================
-- BLOCK 6 — KAFKA SOURCES ON THE CANVAS (Section 4.3; canvas only, no pipeline DDL)
-- =============================================================================
-- There is no CREATE PIPELINE ... FROM @kafka_stage for OpenFlow. Configure the
-- Kafka consumer connector on the OpenFlow canvas and map to a target table.
-- For JVM-based Kafka → Snowflake without OpenFlow, use the Snowflake Kafka
-- Connector (Sections 2–3 of this chapter).

CREATE TABLE IF NOT EXISTS RAW_DB.STREAMING.partner_events (
    event_id        STRING,
    event_type      STRING,
    payload         VARIANT,
    event_timestamp TIMESTAMP_NTZ,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Optional: allow the same runtime role to load Kafka-sourced rows
-- GRANT INSERT, SELECT ON TABLE RAW_DB.STREAMING.partner_events TO ROLE openflow_runtime_role;

-- UI summary: Ingestion » Openflow » Runtimes tab » runtime canvas → Kafka source / consumer,
-- bootstrap servers, topic, SASL_SSL, schema format → route to sink on
-- RAW_DB.STREAMING.partner_events.



-- =============================================================================
-- BLOCK 7 — OPENFLOW CONNECTOR FOR KINESIS (bonus lab, not in the chapter text)
-- =============================================================================
-- Installs the Openflow Connector for Amazon Kinesis Data Streams on the gen 2
-- runtime from Block 4 and lands fraud events in RAW_DB.STREAMING.FRAUD_EVENTS.
--
-- Prerequisites:
--   - Blocks 1-4 done: the techflow_ingest deployment and partner_api_runtime
--     are running (SHOW OPENFLOW RUNTIMES IN SCHEMA OPENFLOW_DB.CONTROL)
--   - AWS Kinesis Data Stream "fraud-events" (deploy with enable_kinesis = true
--     in setup/terraform/aws/terraform.tfvars)
--   - IAM access key from Terraform outputs:
--       terraform output -raw kinesis_connector_access_key_id
--       terraform output -raw kinesis_connector_secret_access_key
--
-- How the connector authenticates:
--   - To AWS: IAM access key and secret (connector parameters).
--   - To Snowflake: SNOWFLAKE_MANAGED (the runtime's session token), so writes
--     run as the runtime's execute-as role, openflow_runtime_role. No service
--     user or key pair is needed. Key-pair auth is an opt-in customization
--     (StandardPrivateKeyService + KEY_PAIR on PublishSnowpipeStreaming).
--
-- Limitations (connector docs):
--   - One stream per connector instance
--   - JSON by default; Avro and Protobuf need extra configuration
--   - No autoscaling: keep MIN_NODES = MAX_NODES on the runtime (Block 4 uses 1/1)
--   - The destination table must exist before you install the connector, and
--     the connector role must own it
--   - DLQ is optional and configured separately (Kinesis DLQ handling page)
--
-- Reference: https://docs.snowflake.com/en/user-guide/data-integration/openflow/connectors/kinesis/setup
-- =============================================================================

-- Step 1: Egress. A Snowflake deployment reaches AWS only through an external
-- access integration on the runtime. The connector calls Kinesis for records
-- and DynamoDB for its checkpoint (lease) table. IF NOT EXISTS matters here:
-- CREATE OR REPLACE on a rule or integration detaches it from the runtime.
USE ROLE ACCOUNTADMIN;

CREATE NETWORK RULE IF NOT EXISTS RAW_DB.STREAMING.kinesis_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = (
    'kinesis.<REPLACE: aws-region, e.g. ca-central-1>.amazonaws.com:443',
    'dynamodb.<REPLACE: aws-region, e.g. ca-central-1>.amazonaws.com:443'
  );

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS fraud_events_kinesis_access
  ALLOWED_NETWORK_RULES = (RAW_DB.STREAMING.kinesis_network_rule)
  ENABLED = TRUE
  COMMENT = 'Openflow Kinesis connector: Kinesis records + DynamoDB checkpoints';

GRANT USAGE ON INTEGRATION fraud_events_kinesis_access TO ROLE openflow_runtime_role;

-- Attach it to the running runtime (ADD keeps partner_api_access attached)
USE ROLE OPENFLOW_ADMIN;
ALTER OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime
  ADD EXTERNAL_ACCESS_INTEGRATIONS = (fraud_events_kinesis_access);
SELECT SYSTEM$WAIT_FOR_STABLE_OPENFLOW_RUNTIMES(600, 'OPENFLOW_DB.CONTROL.PARTNER_API_RUNTIME');

-- Step 2: Destination table. Columns match produce_kinesis_events.py; the
-- connector maps first-level JSON keys to columns by name and fills
-- KINESISMETADATA (stream, shardId, sequenceNumber, approximateArrival...).
-- Schema evolution adds columns for new keys; error logging captures bad rows.
USE ROLE SYSADMIN;
CREATE TABLE IF NOT EXISTS RAW_DB.STREAMING.FRAUD_EVENTS (
    kinesisMetadata OBJECT,
    event_id STRING,
    transaction_id STRING,
    amount NUMBER(12,2),
    merchant_id STRING,
    card_hash STRING,
    event_type STRING,
    risk_score NUMBER(5,2),
    event_timestamp TIMESTAMP_NTZ,
    payload VARIANT
)
  ENABLE_SCHEMA_EVOLUTION = TRUE
  ERROR_LOGGING = TRUE;

-- Row timestamps give a load time without a DEFAULT column
ALTER TABLE RAW_DB.STREAMING.FRAUD_EVENTS SET ROW_TIMESTAMP = TRUE;

-- The connector role must own the table, and the grant must be direct (not
-- inherited). This is a data table, so the "no ownership transfer" rule for
-- gen 2 OpenFlow objects does not apply. Block 2 already granted the role
-- USAGE on RAW_DB, RAW_DB.STREAMING, and BOOK_WH.
USE ROLE SECURITYADMIN;
GRANT OWNERSHIP ON TABLE RAW_DB.STREAMING.FRAUD_EVENTS
  TO ROLE openflow_runtime_role COPY CURRENT GRANTS;

-- Step 3: Install and configure the connector (Openflow UI, not SQL)
--   1. Openflow » Connector library » Openflow connector for Amazon Kinesis
--      Data Streams » Install. Pick partner_api_runtime, then sign in and
--      Allow when the runtime asks for access.
--   2. Right-click the new process group » Parameters:
--        AWS Access Key ID:                 <terraform output>
--        AWS Secret Access Key:             <terraform output>
--        AWS Kinesis Region:                <your region, e.g. ca-central-1>
--        AWS Kinesis Stream Name:           fraud-events
--        AWS Kinesis Application Name:      techflow_fraud_events
--                                           (also the DynamoDB checkpoint table)
--        AWS Kinesis Consumer Type:         SHARED_THROUGHPUT
--        AWS Kinesis Initial Stream Position: TRIM_HORIZON
--        Snowflake Destination Database:    RAW_DB
--        Snowflake Destination Schema:      STREAMING
--        Snowflake Destination Table:       FRAUD_EVENTS
--   3. Right-click the canvas » Enable all Controller Services, then » Start.
-- Gen 2 can also configure connectors with SQL and config.json, but that path
-- is still in Public Preview, so the lab uses the UI.

-- Step 4: Produce test messages to Kinesis (run locally):
--   pip install boto3
--   python3 kafka/produce_kinesis_events.py --stream fraud-events --region <your-region>

-- Step 5: Verify data is flowing (as the table owner)
USE ROLE OPENFLOW_ADMIN;   -- inherits openflow_runtime_role (Block 2)
SELECT COUNT(*) AS rows_loaded,
       MIN(METADATA$ROW_LAST_COMMIT_TIME) AS first_commit,
       MAX(METADATA$ROW_LAST_COMMIT_TIME) AS last_commit
FROM RAW_DB.STREAMING.FRAUD_EVENTS
WHERE METADATA$ROW_LAST_COMMIT_TIME > DATEADD(minute, -15, CURRENT_TIMESTAMP());

SELECT kinesisMetadata:shardId::STRING AS shard_id,
       kinesisMetadata:sequenceNumber::STRING AS sequence_number,
       event_id, amount, risk_score
FROM RAW_DB.STREAMING.FRAUD_EVENTS
LIMIT 10;

-- Cleanup for this block (before chapter4_openflow_teardown.sql):
--   Stop the process group on the canvas and delete it.
--   ALTER OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime
--     REMOVE EXTERNAL_ACCESS_INTEGRATIONS = (fraud_events_kinesis_access);
--   DROP TABLE IF EXISTS RAW_DB.STREAMING.FRAUD_EVENTS;
--   In AWS, delete the DynamoDB table techflow_fraud_events (the connector
--   creates it; terraform destroy does not remove it).
