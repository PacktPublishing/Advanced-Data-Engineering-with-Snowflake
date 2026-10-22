# Chapter 8 Spark-to-Snowpark Migration Project Rules

## Project Overview
A migration project that rehosts TechFlow's PySpark and Spark SQL jobs onto
Snowpark Connect for Spark, runs them as batch workloads through Snowpark
Submit, and uses Snowflake CoCo to translate the middle migration wave. Every
artifact runs against the `gold_db` databases established in Chapters 4 to 7.

## Tech Stack
- Python 3.11 recommended; 3.12 is an alternative. Python 3.10 reaches end of life in October 2026; do not use 3.13 with these packages.
- `snowpark-connect[jdk]` with the bundled JDK for the local translation server
- `snowpark-submit` for the batch path (SPCS compute pool + warehouse SQL)
- `pyspark` 3.5.x client, pinned to the Spark 3.5 line
- Snowflake CLI (`snow`) 3.x for connection management via `connections.toml`
- Snowflake databases: `gold_db` (analytics); warehouse: `BOOK_WH`
- Compute pool: `TECHFLOW_SPARK_POOL` (`CPU_X64_XS`); submitting role: `TECHFLOW_ETL`

## Coding Standards
- Rehost, do not rewrite: keep the DataFrame API surface; aim for the smallest diff.
- Batch jobs in `jobs/` stay pure PySpark with no Snowflake imports, so they run on a plain Spark cluster during the parallel-run window.
- Interactive demos in `snowpark_connect/` start from `snowpark_connect.init_spark_session()` (see `snowpark_connect/session.py`).
- Import Spark `sum` aliased as `sf_sum` to avoid shadowing the builtin.
- Redirect `s3a://` reads to `@lake_stage` paths; route Avro and ORC through external tables.
- Replace `Append`/`Ignore` file writes with table writes or dated overwrite paths.
- Remove `hint()`, `repartition()`, `coalesce()`, `cache()`, `persist()` during cleanup; map intent onto warehouse sizing or a materialized temp table.
- Prefer a `CASE` via `when()` over a Python UDF whenever the logic expresses as SQL (pushes down, vectorizes, removes null-semantics risk).

## Migration Discipline
- Parity is measured, never assumed: normalize types, compare row counts, then an order-independent checksum on a 1% sample (`parity/parity_signature.py`).
- Assign waves only after verifying upstream jobs, downstream consumers, input batches, completion signals, and interface contracts. Unknown dependencies keep the wave pending.
- Keep Spark and migrated jobs running on fixed inputs through the comparison window, using separate validation outputs and one published-output writer.
- Keep any legacy producer needed by a migrated consumer scheduled. Require parity, a successful dependency-chain run, downstream acceptance, and a rollback route before cutover; retire the cluster only when no required workload remains.
- CoCo translations get the five-point review checklist from Chapter 6 plus the parity signature. Flag, do not silently rewrite, anything with no direct equivalent.

## Don'ts
- Never retire the Spark cluster on the strength of a single successful run.
- Never wrap `snowpark-submit` in a Snowflake Task (Tasks execute SQL, not a local CLI); schedule it through an orchestrator's command operator.
- Never hard-code credentials; resolve JDBC and Snowflake secrets from the environment or `connections.toml`, never source.
- Never expect RDD, `pyspark.ml`, or `pyspark.streaming` to migrate through Snowpark Connect; route them to their own destinations.
- Never trust a byte-for-byte schema diff: the type coercions in Section 2.2 make it report false failures on correct migrations.

Consider these rules if they affect your changes.
