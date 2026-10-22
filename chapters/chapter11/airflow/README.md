# How To Review the Airflow 3 Companion

This companion turns manuscript blocks 1-11 into the Airflow 3 baseline DAG plus
the three split DAGs. Shared connections, Cosmos mapping, and the reverse-ETL
push live in `dags/techflow_common.py`. It renders the shared Chapter 6 dbt
project from a checked-in manifest and keeps every Snowflake write behind a
paused DAG.

## Prerequisites

- Python 3.11 or 3.12 for static checks
- A container engine with Compose: Docker, or Rancher Desktop with
  containerd (`nerdctl compose`) for the optional local Airflow interface
- The single shared dbt project at `../../chapter6/dbt/techflow_warehouse`
  (run `dbt deps` in it once so `dbt_packages` exists)
- Reviewed `snowflake_techflow` and `aws_techflow` connections before any live run

## Steps

1. Review the statements Airflow would execute:

   ```text
   dags/sql/load_fraud_scores.sql
   dags/sql/cleanse_transactions.sql
   dags/sql/build_daily_revenue.sql
   dags/sql/build_daily_revenue_incremental.sql
   ```

   `build_daily_revenue.sql` is the manuscript's full-table `INSERT OVERWRITE`
   starting point. The live DAGs run the transaction-wrapped incremental /
   partitioned files with `split_statements=False`.

2. Run the repository's non-mutating tests from `chapters/chapter11`:

   ```bash
   python -m unittest tests.test_companion_static tests.test_prefect_config -v
   ```

   These checks parse source and inspect topology. They do not import Airflow,
   execute SQL, start Docker, or open a Snowflake connection.

3. For an optional local interface, copy the placeholder environment file:

   ```bash
   cp airflow/.env.example airflow/.env
   ```

   Keep placeholders for parse-only review. Replace them only after a separate
   credential and SQL review; `airflow/.env` is ignored by Git.

4. From `airflow/`, build and start the local-only standalone service:

   ```bash
   nerdctl compose build
   nerdctl compose up
   # Docker Desktop / Rancher+moby: docker compose build && docker compose up
   ```

   Open `http://localhost:8080`. The port binds to localhost, example DAGs are
   disabled, and `techflow_transform` is paused when first discovered.

5. Confirm the graph is:

   ```text
   wait_for_scores -> load_scores -> cleanse_transactions
     -> dbt_transform -> build_daily_revenue -> push_segment_for_interval
   ```

   Do not unpause or trigger it during static validation.

## Expected Results

- The DAG imports `DAG` from `airflow.sdk`.
- `CronDataIntervalTimetable` schedules `0 2 * * *` explicitly in UTC.
- Cosmos reads `manifests/manifest.json` without invoking dbt during DAG parse.
- Cosmos executes dbt with `ExecutionMode.LOCAL` only when a DAG run is started.
- Both SQL template paths resolve under
  `/opt/airflow/chapter11/airflow/dags/sql`.

## Troubleshooting

- **Cosmos reports no nightly models**: regenerate `manifests/manifest.json`
  from `../../chapter6/dbt/techflow_warehouse` and confirm `merchant_activity`
  retains the `nightly` tag.
- **The Snowflake profile is incomplete**: the Airflow connection needs login,
  schema, account, database, warehouse, role, and base64 PKCS#8
  `private_key_content`.
- **SQL templates are missing**: confirm Compose mounts the Chapter 11 folder
  at `/opt/airflow/chapter11` and the Chapter 6 folder at `/opt/airflow/chapter6`.
- **dbt fails with a missing-package error**: run `dbt deps` in
  `../../chapter6/dbt/techflow_warehouse` on the host first; the DAG runs Cosmos
  with `install_deps` disabled and reads the pre-built manifest.
- **Failure alerts do nothing locally**: production wires `SmtpNotifier` to
  `on_failure_callback` with an `smtp_default` connection; standalone mode has
  no SMTP configured.

## Additional Information

- Runtime pins target Airflow 3.3.0, common-SQL provider 2.0.2, Snowflake
  provider 6.14.0, Cosmos 1.15.0, and dbt Core/Snowflake 1.12.0.
- The checked-in manifest is the parse-time artifact. Rebuild and review it
  whenever the shared dbt project changes.
- Standalone Airflow and environment-file credentials are local-development
  conveniences. Use separate Airflow services and a secrets backend in a
  deployed environment.
