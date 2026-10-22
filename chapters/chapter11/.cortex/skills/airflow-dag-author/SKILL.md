---
name: airflow-dag-author
description: Author Airflow 3 Snowflake DAGs with current common-SQL, Cosmos manifest, timetable, and key-pair patterns from Chapter 11.
---

# airflow-dag-author

Use this skill to author or review Airflow 3 DAGs that orchestrate reviewed
Snowflake SQL and dbt Core projects. It generates files for review and static
parsing only; it never starts Airflow, triggers a DAG, installs packages, or
opens a Snowflake connection.

## Required project shape

1. Put DAGs under `airflow/dags/`.
2. Put reviewed SQL templates under `airflow/dags/sql/`.
3. Put pre-built dbt artifacts under `airflow/manifests/`.
4. Keep the dbt source project outside the DAG folder and mount both at stable
   absolute container paths.
5. Pin providers, Cosmos, dbt, and the Airflow image in source control.
6. Provide a local-only Compose setup with the DAG paused by default and its
   web port bound to localhost.

## Airflow 3 rules

1. Import the public DAG interface exactly:

   ```python
   from airflow.sdk import DAG
   ```

2. Use `SQLExecuteQueryOperator` from
   `airflow.providers.common.sql.operators.sql`. Never generate the removed
   Snowflake-specific SQL operator.
3. Do not pass a bare cron string. Construct `CronDataIntervalTimetable` with
   the cron expression and an explicit Pendulum timezone.
4. Use a fixed, timezone-aware `start_date`, `catchup=False`, and
   `max_active_runs=1` unless the reviewed design requires backfills or overlap.
5. Set `template_searchpath` so every SQL path resolves identically in the
   scheduler, worker, and local container.
6. Keep task IDs and Python names in lowercase snake_case.

## Cosmos rules

1. Use dbt Core, not Fusion, for this companion.
2. Reuse the Airflow Snowflake connection through:

   ```python
   from cosmos.profiles import SnowflakePrivateKeyPemProfileMapping
   ```

   The connection supplies the service user, account, and
   `private_key_content`. Supply non-secret database, schema, warehouse, role,
   and query tag through `profile_args`.
3. Parse a reviewed artifact explicitly:

   ```python
   ProjectConfig(manifest_path=manifest_path, project_name="techflow")
   RenderConfig(load_method=LoadMode.DBT_MANIFEST)
   ```

   Do not run `dbt ls`, `dbt deps`, or `dbt parse` during DAG import.
4. Make worker execution explicit:

   ```python
   ExecutionConfig(
       execution_mode=ExecutionMode.LOCAL,
       dbt_project_path=dbt_project_path,
   )
   ```

   LOCAL means dbt and `dbt-snowflake` must be installed in the Airflow image.
5. Filter the manifest with dbt selectors such as `select=["tag:nightly"]`.
6. Wire the complete control dependency explicitly:

   ```python
   cleanse >> dbt_transform >> build_daily_revenue
   ```

## Snowflake and SQL safety

1. Reference a fixed Airflow connection ID. Never construct connection IDs,
   object names, SQL, file paths, or target URLs from untrusted input.
2. Keep credentials out of DAGs, Compose files, and committed environment
   files. A committed `.env.example` may contain placeholders only when `.env`
   is ignored.
3. Treat `SnowflakePrivateKeyPemProfileMapping` as secret-injection plumbing,
   not secret storage. Use a secrets backend in deployed environments.
4. Keep Snowflake computation in SQL or dbt; never pull warehouse data into an
   Airflow worker for transformation.
5. Preserve reviewed statement text. If the manuscript's
   `INSERT OVERWRITE` is copied, add a warning that it replaces the entire
   target table and ensure static validation only reads it.
6. Confirm no other scheduler or writer targets
   `gold_db.transactions.merchant_daily_revenue` before a later live run.

## Runtime assumptions

The Chapter 11 companion is pinned to:

- Apache Airflow 3.3.0 on Python 3.11
- common-SQL provider 2.0.2
- Snowflake provider 6.14.0
- Astronomer Cosmos 1.15.0
- dbt Core and dbt-snowflake 1.12.0

When updating one pin, review all five together and regenerate the dbt manifest.

## Static verification checklist

1. Parse Python with `ast` or `compile()` without importing Airflow.
2. Parse the checked-in manifest as JSON and confirm the selected dbt nodes
   exist.
3. Confirm both SQL template files exist at the container-visible paths.
4. Confirm the exact three-stage dependency chain is present.
5. Confirm the DAG contains the public SDK import, explicit UTC timetable,
   manifest load mode, LOCAL execution mode, and PEM profile mapping.
6. Confirm the local service is paused, binds only to localhost, and contains
   no working credential.
7. Show every `CALL`, `INSERT OVERWRITE`, and other mutating statement to a
   human. Never run SQL, a DAG, Docker, or dbt as part of static verification.

## Limitations

Static parsing does not prove that Airflow providers are mutually installable,
the Snowflake connection exists, the private key is valid, the service role has
privileges, the manifest matches the deployed dbt project, or the SQL succeeds.
Those checks require a separately approved runtime and human review.
