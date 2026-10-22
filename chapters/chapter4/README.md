# How To Run Chapter 4 (Real-Time Ingestion and CDC)

This chapter mixes **Snowflake-native CDC** (streams, MERGE, dynamic tables) with **optional** streaming integrations (Kafka, OpenFlow, Kinesis, Event Hubs). Follow the path that matches your account and cloud setup.

## Prerequisites

- **Chapters 2 and 3 completed** — the scripts in those chapters create `RAW_DB`, `SILVER_DB`, `BOOK_WH`, and the schemas that Chapter 4 depends on. Run them first.
- Completed [setup/snowflake_setup.sql](../../setup/snowflake_setup.sql) — `BOOK_WH`, `UTIL`, network policy, etc.
- Role **`ACCOUNTADMIN`** (or equivalent) to create roles, integrations, and objects.

## Step-by-step: Snowflake scripts

1. Open the setup script for the section you are following: [chapter4_kafka_setup.sql](chapter4_kafka_setup.sql) (Sections 2-3 + Event Hubs), [chapter4_openflow_setup.sql](chapter4_openflow_setup.sql) (Section 4, with [chapter4_openflow_teardown.sql](chapter4_openflow_teardown.sql) to remove it), or [chapter4_cdc_setup.sql](chapter4_cdc_setup.sql) (Section 5). The three files are independent.
2. Search for `<REPLACE:` and fill in every placeholder **before** running that block.
3. Run **section by section** (do not blindly run the whole file if you lack Kafka/OpenFlow/paid features).

### What each major section needs

| Section | Topic | Needs |
|---------|--------|--------|
| 2.3–3.2 | Kafka Connector + Snowpipe Streaming | Kafka (local Docker, **MSK**, or similar) + Kafka Connect + RSA user setup — see [setup/TESTING.md](../../setup/TESTING.md) and [kafka/produce_fraud_events_msk.py](kafka/produce_fraud_events_msk.py) |
| 4.1a | OpenFlow admin role, OAuth, infra schema | **Before** Launch Openflow: `OPENFLOW_ADMIN` with gen 2 privileges, user `DEFAULT_ROLE`, **SYSADMIN** grant, `OPENFLOW_DB.CONTROL`; ORGADMIN accepts terms under **Admin » Terms** |
| 4.1b | OpenFlow deployment and runtime (SQL) | Blocks 3-4: `CREATE OPENFLOW DEPLOYMENT` + `CREATE OPENFLOW RUNTIME` (gen 2), wait functions, GRANT templates; at most three Snowflake deployments per account |
| 4.2 | REST + OpenFlow (partner + Alpha Vantage FX lab) | **Paid** account; Block 2 creates **two** network rules + **`partner_api_access`** + **`fx_daily_rates`** (free-tier Alpha Vantage key required) + execute-as role; canvas flow in §4.2 of the chapter or import `rest-api-ingestion.json`; [chapter4_openflow_teardown.sql](chapter4_openflow_teardown.sql) when done |
| 4.3 | OpenFlow Kafka | **OpenFlow** canvas with Kafka processors; **no** `CREATE PIPELINE` / `@kafka_stage` — use **Kafka Connector** (Secs 2–3) for JVM-only ingestion |
| Bonus | OpenFlow Kinesis | Block 7 of `chapter4_openflow_setup.sql` (not in the chapter text): gen 2 runtime + Kinesis/DynamoDB egress, AWS Kinesis stream + access keys (see [setup/SETUP.md](../../setup/SETUP.md) optional steps) |
| 4.5 | Event Hubs + Kafka Connect | Azure Event Hubs + Kafka Connect worker configured for SASL_SSL |
| 5.x | Streams, MERGE, dynamic tables, schema evolution | **No external streaming** — works on most accounts once `RAW_DB` / `SILVER_DB` exist |

## OpenFlow lab (Sections 4.1a–4.2)

Use this when following **Building Visual Integration Pipelines with OpenFlow** and the REST/Alpha Vantage FX or partner API lab. Everything here is **OpenFlow gen 2**: Snowflake retired gen 1 deployment creation on 2026-09-09, and gen 2 deployments and runtimes are SQL objects.

### Order of operations

1. **Block 1** in [chapter4_openflow_setup.sql](chapter4_openflow_setup.sql): `OPENFLOW_ADMIN` with the gen 2 account privileges (`CREATE OPENFLOW DEPLOYMENT`, `CREATE DATABASE`, `CREATE INTEGRATION`, `CREATE COMPUTE POOL`), grants to **SYSADMIN** and your user, `DEFAULT_ROLE` + `DEFAULT_SECONDARY_ROLES` (Openflow login blocks **ACCOUNTADMIN** as default role), and the infrastructure schema **`OPENFLOW_DB.CONTROL`** that holds the runtime. **ORGADMIN**: accept the Openflow terms of service once under **Admin » Terms**.
2. **Block 2**: both landing tables, **`alphavantage_network_rule`** + **`partner_api_network_rule`**, one **`partner_api_access`** integration listing both, the Alpha Vantage API key secret, and the execute-as role **`openflow_runtime_role`** with its grants (the UI may show it as **`OPENFLOW_RUNTIME_ROLE`**). Network rules and the integration use `CREATE ... IF NOT EXISTS`: `CREATE OR REPLACE` silently detaches them from every runtime that references them, so change them with `ALTER`.
3. **Block 3**: `CREATE OPENFLOW DEPLOYMENT techflow_ingest` (Snowflake deployment) and a wait until it is ACTIVE (5-10 minutes).
4. **Block 4**: `CREATE OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime` in that deployment, with `EXECUTE_AS_ROLE = openflow_runtime_role` and `EXTERNAL_ACCESS_INTEGRATIONS = (partner_api_access)`, then a wait (3-5 minutes). A gen 2 runtime has no warehouse setting: the flow uses `BOOK_WH` through the grants on the execute-as role.
5. **Snowsight UI**: **Ingestion » Openflow » Launch Openflow » Runtimes** tab, open `PARTNER_API_RUNTIME`, then import [rest-api-ingestion.json](rest-api-ingestion.json) as a process group or wire it by hand (InvokeHTTP → JoltTransformJSON → SplitJson `$.rates[*]` → PutSnowpipeStreaming; see **Block 5** and chapter section *Building the processor chain, Alpha Vantage FX_DAILY*).
6. **When you finish the chapter**: run [chapter4_openflow_teardown.sql](chapter4_openflow_teardown.sql). The deployment's management compute pool bills for as long as the deployment exists, even with the runtime suspended. Between sessions, `ALTER OPENFLOW RUNTIME ... SUSPEND` is enough.

Headless **Cortex** batch (optional): `prompts/chapter4-openflow-nifi-workflow.txt` with `cortex -c <connection> --bypass -p "$(cat …)"`.

### SQL vs UI in gen 2

| Action | SQL | UI |
|--------|-----|-----|
| Create / terminate / drop **deployment** | `CREATE OPENFLOW DEPLOYMENT`, `ALTER ... TERMINATE`, `DROP` | Yes |
| Create / suspend / resume / resize / drop **runtime**, bind EAIs | `CREATE OPENFLOW RUNTIME`, `ALTER OPENFLOW RUNTIME ... SUSPEND / RESUME / SET NODE_TYPE_TIER / ADD EXTERNAL_ACCESS_INTEGRATIONS`, `DROP` | Yes |
| Share access | `GRANT USAGE / MONITOR ON OPENFLOW DEPLOYMENT`, `GRANT USAGE / OPERATE / MONITOR ON OPENFLOW RUNTIME` plus `USAGE` on `OPENFLOW_DB` and its schema | Yes |
| Event table for telemetry | `ALTER OPENFLOW DEPLOYMENT ... SET EVENT_TABLE` | Optional |
| Wire processors on the **NiFi canvas** (custom flows) | No | Yes (or import the flow JSON) |

Gen 2 access rules worth knowing: `USAGE` on a deployment does **not** reach its runtimes, users only see deployments they hold a privilege on, and Snowflake warns against `GRANT OWNERSHIP` on gen 2 OpenFlow objects. An account holds at most **three** Snowflake deployments, gen 1 and gen 2 combined.

**Cost:** `SNOWFLAKE.ACCOUNT_USAGE.OPENFLOW_USAGE_HISTORY` returns rows for **BYOC** deployments only. For this lab (Snowflake deployment) query `METERING_HISTORY` with `SERVICE_TYPE = 'OPENFLOW_COMPUTE_SNOWFLAKE'` (Block 5). `*_CONTROL_POOL` rows are the deployment's management services, `*_SMALL / _MEDIUM / _LARGE` rows are runtimes.

**Existing gen 1 deployment?** It keeps working. To migrate: suspend all its runtimes, then **Migrate** from the deployment's action menu in the Openflow UI. You need OWNERSHIP on the deployment and OPERATE on every runtime, and runtimes land as schema-scoped objects, so re-grant `USAGE` on that database and schema to any other role that used them.

**References:** [Quickstart: gen 2 Openflow](https://docs.snowflake.com/en/user-guide/data-integration/openflow/gen2/quickstart), [Openflow gen 1 and gen 2](https://docs.snowflake.com/en/user-guide/data-integration/openflow/gen2/openflow-generations), [CREATE OPENFLOW DEPLOYMENT](https://docs.snowflake.com/en/sql-reference/sql/create-openflow-deployment), [CREATE OPENFLOW RUNTIME](https://docs.snowflake.com/en/sql-reference/sql/create-openflow-runtime), [Execute-as role and EAIs](https://docs.snowflake.com/en/user-guide/data-integration/openflow/setup-openflow-spcs-create-rr), [Snowflake deployment cost](https://docs.snowflake.com/en/user-guide/data-integration/openflow/cost-spcs), [Migrate gen 1 to gen 2](https://docs.snowflake.com/en/user-guide/data-integration/openflow/gen2/migrate-deployment-runtime).

### Trial account

- Run **Section 5** (streams, MERGE, dynamic table, `evolve_schema`) after creating the objects in earlier DDL blocks that do not depend on paid features.
- **Skip** (or do not run) blocks that create **network rules**, **external access integrations**, **secrets** tied to paid features, or **OpenFlow pipelines** if your account returns errors.

## Optional: test data for Sections 5.1–5.4

After the DDL in `chapter4_cdc_setup.sql` has succeeded for landing tables, streams, and silver objects, run:

- [chapter4_test_data.sql](chapter4_test_data.sql)

That script inserts sample customers and VARIANT rows so you can query streams and test MERGE / views.

## Optional: streaming infrastructure (pick one or more)

| Path | When to use | Doc / command |
|------|-------------|----------------|
| **Local Kafka** | Easiest for Sections 2.3–2.4 without AWS MSK | [kafka/README.md](kafka/README.md) — `docker compose up -d` |
| **AWS MSK + MSK Connect** (recommended) | Production-style managed Kafka + managed Kafka Connect | [setup/SETUP.md](../../setup/SETUP.md) — `enable_msk`, `enable_msk_connect` (Terraform deploys the Snowflake sink connector automatically) |
| **AWS MSK + self-managed Connect** | MSK without managed Connect (bastion-based) | [setup/TESTING.md](../../setup/TESTING.md) Phase C Path 2 |
| **AWS MSK + Kinesis** | Book Terraform optional flags | [setup/SETUP.md](../../setup/SETUP.md) — `enable_msk`, `enable_kinesis` |
| **Azure Event Hubs** | Section 4.5 | [setup/terraform/azure/](../../setup/terraform/azure/) + curl config in `chapter4_kafka_setup.sql` |

## Expected results (quick checks)

- **Streaming table** — After Kafka connector is running: rows appear in `RAW_DB.STREAMING.FRAUD_EVENTS` and `_loaded_at` updates.
- **OpenFlow REST lab** — After Section 4.2 SQL and the §4.2 NiFi chain against Alpha Vantage FX_DAILY: `SELECT COUNT(*) FROM RAW_DB.STREAMING.FX_DAILY_RATES` increases (about **100 rows per successful InvokeHTTP run** in append mode; stop the flow after verification to avoid duplicates).
- **CDC** — After `chapter4_test_data.sql`: `SELECT * FROM RAW_DB.CDC.CUSTOMER_CHANGES` shows `METADATA$ACTION` / `METADATA$ISUPDATE`.
- **Silver MERGE** — Run the two `MERGE` statements in Section 5.2 after consuming or re-querying the stream as the book describes.
- **Dynamic table** — `SILVER_DB.CUSTOMERS.DIM_CUSTOMER_DYNAMIC` refreshes on a lag (warehouse must run).

## Troubleshooting

- **`Database 'RAW_DB' does not exist`** — Create `RAW_DB` / `SILVER_DB` (see Prerequisites).
- **`External access` / `OpenFlow` errors** — Skip those sections on trial or request feature enablement from Snowflake.
- **Openflow OAuth login fails**: you cannot use **ACCOUNTADMIN** (or ORGADMIN / SECURITYADMIN / GLOBALORGADMIN) as **default role**. Run **Block 1** in `chapter4_openflow_setup.sql` (`OPENFLOW_ADMIN`, grant to user + **SYSADMIN**, `DEFAULT_ROLE` + `DEFAULT_SECONDARY_ROLES`). **ORGADMIN** must accept the Openflow terms once under **Admin » Terms**.
- **`CREATE OPENFLOW DEPLOYMENT` fails on the limit**: the account already has three Snowflake deployments (gen 1 + gen 2). Reuse one by name in Block 4, or remove an unused one.
- **Runtime cannot reach Alpha Vantage after re-running Block 2**: an older copy of the script used `CREATE OR REPLACE` on the integration, which detaches it from the runtime. Re-attach with `ALTER OPENFLOW RUNTIME OPENFLOW_DB.CONTROL.partner_api_runtime ADD EXTERNAL_ACCESS_INTEGRATIONS = (partner_api_access);`
- **Kafka Connect cannot reach Snowflake** — Check account URL, role name (`STREAMING_INGEST_ROLE` must match `streaming_ingest_role` creation — Snowflake role names are case-insensitive but connector config must match), RSA key on user, and warehouse grant on `streaming_ingest_role`.
- **MCP / PAT issues** — Use Snowsight or SnowSQL; PAT is optional for Cursor only.

## Related files

- [chapter4_kafka_setup.sql](chapter4_kafka_setup.sql) — Kafka connector, streaming mode, DLQ, tuning, Event Hubs
- [chapter4_openflow_setup.sql](chapter4_openflow_setup.sql) — OpenFlow gen 2: admin role + infra schema, egress + grants, deployment, runtime, canvas walkthrough (incl. Jolt spec) + cost query, Kafka on the canvas, Kinesis
- [chapter4_openflow_teardown.sql](chapter4_openflow_teardown.sql) — suspends, terminates, and drops the OpenFlow runtime and deployment
- [rest-api-ingestion.json](rest-api-ingestion.json) — Alpha Vantage FX_DAILY flow definition to import onto the runtime canvas
- [chapter4_cdc_setup.sql](chapter4_cdc_setup.sql) — Streams, transactional MERGE pair + task, Dynamic Tables, schema evolution
- [chapter4_test_data.sql](chapter4_test_data.sql) — optional inserts for CDC labs
- [kafka/](kafka/) — Docker Compose + `produce_fraud_events.py` / `produce_kinesis_events.py`
