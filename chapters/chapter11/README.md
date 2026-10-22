# How To Compare Snowflake Orchestrators (Chapter 11)

This companion project turns every Chapter 11 code block into reviewable,
runnable files for Apache Airflow, Prefect, and Dagster. Each tool builds the
same cross-system workflow: wait for the fraud team's scores in S3, load them,
run the cleanse and the dbt project, rebuild the revenue aggregate, and push the
high-risk segment to a marketing API. It also supplies the SQL, dbt project,
score simulator, mock marketing service, configuration, and static checks that
the manuscript references but does not show.

The validation path is intentionally non-mutating. It imports definitions,
checks topology, parses configuration, and compiles code without running a
Snowflake statement, deployment, schedule, flow, DAG, or asset.

## Prerequisites

- Python 3.11 or 3.12
- `uv` for isolated Python environments
- A container engine with Compose: Docker, or Rancher Desktop with containerd
  (`nerdctl compose`). `commands/validate.sh` accepts either.
- Chapter 9 objects, including:
  - `ops_db.pipelines.run_cleanse()`
  - `silver_db.transactions.transactions_clean`
  - `gold_db.transactions.merchant_daily_revenue`
  - `BOOK_WH`
- A dedicated Snowflake `TYPE=SERVICE` user for any later live exercise. Run
  `sql/setup.sql` by hand (review only) to create `TRANSFORMER_RL`,
  `SVC_ORCHESTRATOR`, the `techflow_ml_integration` storage integration, the
  `raw_db.streaming.fraud_scores` landing table, the `ml_scores_stage` external
  stage, and the grants this chapter needs (warehouse/schema USAGE, CREATE TABLE
  and CREATE VIEW on the dbt schemas, and imported privileges on `SNOWFLAKE` for
  `ACCOUNT_USAGE`). That script is a local sandbox shortcut, not the Chapter 10
  production path.
- An AWS S3 bucket (`techflow-ml`) reached through the dedicated
  `techflow_ml_integration` storage integration, and AWS credentials for the S3
  wait step.
- An unencrypted key pair held outside the repository (the same file every tool
  loads); each tool's configuration notes its encrypted-key variant.
- The shared Chapter 6 dbt project at `../chapter6/dbt/techflow_warehouse`. Run
  `dbt deps` in it once and copy `profiles.yml.example` to `profiles.yml`.

Before enabling any orchestrator, run `sql/suspend_chapter9.sql` (review only)
so the Chapter 9 task graph is not writing the same target table. One table must
have one active writer.

## Folder Layout

| Path | Purpose |
|------|---------|
| `airflow/dags/techflow_transform.py` | Baseline DAG (Sections 1.1–1.4) |
| `airflow/dags/fraud_scores_ingest.py` | Split DAG: S3 wait + COPY + partitioned asset |
| `airflow/dags/transaction_transform.py` | Split DAG: cleanse, Cosmos dbt, bounded gold write |
| `airflow/dags/marketing_activation.py` | Split DAG: asset-triggered reverse ETL + deadline |
| `airflow/dags/techflow_common.py` | Shared connections, Cosmos mapping, push, query tags |
| `prefect/` | Prefect flow, connector-block setup, and deployment |
| `dagster/` | Four partitioned assets, S3 sensor, resource, dbt component |
| `../chapter6/dbt/techflow_warehouse/` | The single shared dbt project (no chapter-11 copy) |
| `upload_scores.py` | Simulator that drops a sample `fraud_scores_<date>.parquet` into S3 |
| `marketing_api/` | Mock endpoint that honors `Idempotency-Key` |
| `sql/` | `setup.sql`, `suspend_chapter9.sql`, `teardown.sql` (review only), `set_query_tag.sql` |
| `.cortex/skills/` | Airflow, Prefect, and Dagster authoring skills |
| `tests/` | Non-mutating companion-code checks; `test_dags.py` needs Airflow |
| `CODE_BLOCK_MAP.md` | Mapping from all 25 manuscript code blocks to files |
| `AGENTS.md` | Tech stack and coding standards for this companion |

## Steps

1. Review the manuscript-to-file mapping.

   ```bash
   less CODE_BLOCK_MAP.md
   ```

   The map identifies pedagogical fragments that had to be combined and records
   corrections needed for current package APIs.

2. Run the safe validation suite.

   ```bash
   ./commands/validate.sh
   ```

   This command performs syntax, import, topology, YAML, Compose, dbt parse, and
   definition checks only. It does not trigger an orchestrator or connect to
   Snowflake.

3. Review the Airflow example.

   ```bash
   less airflow/dags/techflow_transform.py
   ```

   Confirm that the DAG uses `airflow.sdk`, an explicit UTC data-interval
   timetable, a deferrable `S3KeySensor`, the current Cosmos private-key
   mapping (in `techflow_common.py`), manifest parsing, a retry-safe reverse-ETL
   push, and:

   ```text
   wait_for_scores -> load_scores -> cleanse_transactions
     -> dbt_transform -> build_daily_revenue -> push_segment_for_interval
   ```

   The three split DAGs are `fraud_scores_ingest.py`, `transaction_transform.py`,
   and `marketing_activation.py`.

4. Review the Prefect example.

   ```bash
   less prefect/transform.py
   less prefect/setup_blocks.py
   less prefect/deploy.py
   ```

   `setup_blocks.py` and `deploy.py` perform external writes when run. They are
   separate modules so importing `transform.py` never saves a block or creates a
   deployment.

5. Review the Dagster example.

   ```bash
   less dagster/src/techflow_orchestration/definitions.py
   ```

   The project loads its dbt component, merges it with the four Python assets,
   the resource, and the S3 `scores_sensor` trigger, and validates definitions
   without materializing them. `schedules.py` holds the time-driven alternative.

6. (Optional) Run the workflow end to end against a live account.

   ```bash
   # Drop a sample scores file (uses your AWS credential chain).
   python upload_scores.py --date "$(date -v-1d +%F)"
   # Start Airflow plus the mock marketing API.
   cd airflow && nerdctl compose up   # or: docker compose up
   ```

   `nerdctl compose logs marketing-api` (or `docker compose logs`) shows the
   received POST and its row count
   once the DAG runs. Requires the reviewed `sql/setup.sql` to have been applied.

7. Review data-modifying SQL before any live run.

   ```bash
   less sql/setup.sql
   less airflow/dags/sql/cleanse_transactions.sql
   less airflow/dags/sql/build_daily_revenue.sql
   less airflow/dags/sql/build_daily_revenue_incremental.sql
   less airflow/dags/sql/load_fraud_scores.sql
   less sql/set_query_tag.sql
   ```

   Snowflake `INSERT OVERWRITE` replaces the entire target table, not one date
   partition; the live DAGs run `build_daily_revenue_incremental.sql` /
   `build_daily_revenue_partitioned.sql`. The companion never executes any of
   these during validation.

## Expected Results

- Python compilation reports no syntax errors.
- Unit tests account for all 25 fenced manuscript blocks.
- Airflow parsing exposes the baseline DAG
  `wait_for_scores -> load_scores -> cleanse_transactions -> dbt_transform ->
  build_daily_revenue -> push_segment_for_interval`, plus the three split DAGs,
  with the dbt group rendered by Cosmos.
- Prefect imports without creating a block, flow run, work pool, or deployment.
- `dbt parse` resolves the `tag:nightly` model and its Snowflake source.
- `dg check defs` loads four partitioned assets, the S3 sensor, and the dbt component.
- Docker Compose configuration renders the `marketing-api` service without
  embedded credentials.
- No Snowflake query appears in query history because validation opens no
  Snowflake connection.

## Troubleshooting

- **Airflow cannot import the Cosmos profile mapping**: install the dependency
  versions declared under `airflow/`; the class is
  `SnowflakePrivateKeyPemProfileMapping`, not the class printed in the draft.
- **Cosmos finds zero models**: regenerate `airflow/manifests/manifest.json`
  from `../chapter6/dbt/techflow_warehouse` and confirm `merchant_activity`
  retains the `nightly` tag.
- **Prefect warns about unresolved futures**: keep `push.result()` inside the
  flow so terminal failures propagate before the flow returns.
- **Prefect wait never fails on bad credentials**: the `retry_condition_fn`
  retries only a missing-key (404) error, so a 403 fails on the first attempt.
- **Prefect cannot pull deployment code**: use a full 40-character Git commit
  SHA and ensure Git plus project dependencies exist in the runtime.
- **Dagster shows an unconnected dbt source**: confirm the dbt `source()` asset
  key matches the handwritten `transactions_clean` asset.
- **Dagster fails on the dbt component**: the shared Chapter 6 project needs a
  `profiles.yml` in its folder; copy `profiles.yml.example` to `profiles.yml`.
- **Using an encrypted key instead**: add `private_key_password` to the Dagster
  resource and set `SNOWFLAKE_PRIVATE_KEY_PASSWORD`; the default is unencrypted.
- **A validation command attempts to run SQL**: stop it. The expected validation
  path only parses and imports code.

## Additional Information

- `CODE_BLOCK_MAP.md` maps every manuscript block to its companion file and notes
  where a fragment was combined or corrected for a current API.
- All three orchestrators implement the full cross-system workflow: the S3 wait
  (deferrable sensor in Airflow, retry-driven poll in Prefect, out-of-run sensor
  in Dagster), the dbt transform, and the reverse-ETL push to `marketing-api`.
- Live testing requires explicit human review of the SQL, configured secrets,
  active orchestrator services, and a decision about which scheduler owns the
  target table.
