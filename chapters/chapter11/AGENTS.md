# Chapter 11 External Orchestration Project Rules

## Project Overview

This chapter compares Apache Airflow 3, Prefect 3, and Dagster by expressing the
same TechFlow Snowflake workflow in each tool. The companion project builds on
the objects from Chapter 9 and the ownership boundaries from Chapter 10.

## Tech Stack

- Python 3.11 or 3.12
- Apache Airflow 3 with the Snowflake/common-SQL/Amazon providers and Cosmos
- Prefect 3 with `prefect-snowflake`, `prefect-dbt`, `boto3`, and `httpx`
- Dagster with `dagster-dg-cli`, `dagster-snowflake`, `dagster-dbt`,
  `dagster-aws`, and `httpx`
- dbt Core with `dbt-snowflake`; the single shared project is Chapter 6's
  `../chapter6/dbt/techflow_warehouse` (no chapter-11 copy)
- Snowflake databases `raw_db`, `silver_db`, `gold_db`, and `ops_db`
- Warehouse `BOOK_WH`, S3 bucket `techflow-ml`, and the `marketing-api` mock
- Key-pair auth with an unencrypted key file (encrypted-key variant noted per tool)

## Coding Standards

- Use the Airflow 3 public interface under `airflow.sdk`.
- Use `SQLExecuteQueryOperator`; `SnowflakeOperator` was removed in provider 6.
- Declare the Airflow data-interval timetable and timezone explicitly.
- Resolve every submitted Prefect future before its flow returns.
- In Dagster, load component definitions and merge them with Python definitions.
- Do not add `from __future__ import annotations` to Dagster asset or sensor
  modules: `dg check defs` inspects runtime types on `context`.
- Encode dbt dependencies with `ref()` or `source()`, never inferred table names.
- Read credentials from orchestrator-managed secrets or environment references.
- Use lowercase snake_case for Python names, task IDs, asset keys, and filenames.
- Keep Snowflake sessions and cursors scoped to one task or asset.
- Bind incremental work to a fixed half-open interval: `[start, end)`.

## Object Ownership

- Chapter 9 owns the Snowflake task graph and stored procedure.
- Chapter 10 owns infrastructure and deployment objects.
- Chapter 11 creates `TRANSFORMER_RL` and `SVC_ORCHESTRATOR` in `sql/setup.sql`.
  Orchestrators call existing pipeline objects; they do not redefine them.
- Only one active scheduler or writer may target
  `gold_db.transactions.merchant_daily_revenue` at a time.

## Safety

- Never execute `CALL`, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `ALTER`, `CREATE`,
  `DROP`, `TRUNCATE`, `GRANT`, `REVOKE`, or a deployment from automated tests.
- Static checks may parse SQL text, import definitions, and inspect topology.
- Show every data-modifying statement to a human before a later live run.
- Never commit private keys, passphrases, tokens, connection URLs, `.env` files,
  runtime databases, logs, or generated dbt targets.

## Don'ts

- Never assume Snowflake `INSERT OVERWRITE` replaces one logical partition; it
  replaces the entire target table.
- Never create an Airflow, Prefect, or Dagster run during companion validation.
- Never materialize Dagster assets as part of `dg check`.
- Never create or save Prefect blocks during import or unit tests.
- Never let Docker Compose examples contain working credentials.
