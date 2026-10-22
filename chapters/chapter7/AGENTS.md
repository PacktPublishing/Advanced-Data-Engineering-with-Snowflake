# Chapter 7 Snowpark Project Rules

## Project Overview
A Snowpark Python project that demonstrates the DataFrame API, pandas on
Snowflake, scalar and vectorized UDFs, UDTFs, stored procedures, and the
local testing framework. Every artifact runs against the `gold_db` and
`silver_db` databases established in Chapters 4 to 6.

## Tech Stack
- Python 3.11
- snowflake-snowpark-python 1.20+ with modin[snowflake] for pandas on Snowflake
- snowflake-ml-python 1.6+ for the Feature Store and Model Registry sketch
- pytest 8+ with the in-memory `local_testing=True` Snowpark engine
- Snowflake databases: `raw_db` (raw), `silver_db` (clean), `gold_db` (analytics)
- Warehouses: `BOOK_WH` for ad hoc and the chapter examples, `BOOK_WH_XS_SO` Snowpark-optimized for UDF benchmarks

## Coding Standards
- Build sessions with `snowpark.session.build_session()`; never instantiate `Session.builder` ad hoc.
- Import Snowpark `sum` aliased as `sf_sum` to avoid shadowing the builtin.
- Type-hint every UDF/UDTF/sproc signature and declare explicit `input_types` and `return_type` on every decorator.
- Pin `is_permanent=True`, `replace=True`, and an explicit `stage_location` on every `@udf`, `@pandas_udf`, `udtf`, and `@sproc` registration.
- Vectorize UDFs whenever the logic is row-independent and runs on > 1M rows; fall back to scalar UDFs only when the rewrite cost exceeds the throughput gain.
- Parameterize stored procedure SQL with `session.sql(..., params=[...])` (qmark binding), never string-concatenate user input.

## Don'ts
- Never call `.to_pandas()` inside a DataFrame chain meant to push down.
- Never iterate rows in Python by calling `.collect()` and looping; pushdown breaks immediately.
- Never register UDFs without `replace=True` in the chapter examples. The deploy script reruns idempotently.
- Never store credentials in source; resolve everything via the Snowflake CLI `config.toml` profile referenced by `connection_name`.
- Never disable the local testing framework to save time. The unit tier is the cheapest place to catch regressions.
