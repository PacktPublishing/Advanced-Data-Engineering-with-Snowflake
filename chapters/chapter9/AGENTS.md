# Chapter 9 Native Orchestration Project Rules

## Project Overview
A SQL-only project that builds TechFlow's transaction pipeline using Snowflake's
native orchestration primitives: tasks and task graphs, streams and triggered
tasks, and Dynamic Tables. Every object runs against the medallion databases
established in Chapters 4 to 8 (`raw_db`, `silver_db`, `gold_db`) plus the
dedicated orchestration database `ops_db` (schema `pipelines`) on the `BOOK_WH`
warehouse. All tasks live in `ops_db.pipelines` because a task graph must share
one schema; their bodies write cross-database with fully qualified names.

## Tech Stack
- Snowflake SQL (no Python, no external tooling beyond `snow` CLI or Snowsight)
- Snowflake CLI (`snow`) 3.x for running scripts outside Snowsight
- Snowflake databases: `raw_db` (landing), `silver_db` (clean), `gold_db`
  (analytics), `ops_db` (orchestration: tasks, finalizer log, `run_cleanse()`)
- Warehouse: `BOOK_WH`
- CoCo skill: `task-dag-author` for AI-assisted task graph authoring (Section 5.3)

## Coding Standards
- One writer per table. Never point a scheduled task and a Dynamic Table at the
  same target. If a table is a Dynamic Table, every value comes from its SELECT.
- Set `REFRESH_MODE` explicitly on every Dynamic Table that matters. Never rely
  on AUTO for production pipelines.
- Set `SUSPEND_TASK_AFTER_NUM_FAILURES` on every scheduled root task.
- Use `TARGET_LAG = 'DOWNSTREAM'` on intermediate Dynamic Tables in a chain
  instead of hand-tuning a fixed lag.
- Consume streams inside a committed DML statement (or an explicit transaction)
  so the offset advances atomically with the writes.
- Guard every triggered task with `WHEN SYSTEM$STREAM_HAS_DATA(...)` to prevent
  empty runs.
- Every task is created in a suspended state. Resume child tasks before the root,
  or use `SYSTEM$TASK_DEPENDENTS_ENABLE` for graphs.
- Every task in one graph lives in one schema (`ops_db.pipelines`). Cross-schema
  `AFTER` / `FINALIZE` is not allowed; write cross-database from the task body
  using fully qualified names instead.
- Cast VARIANT payloads with `TRY_TO_DECIMAL` / `TRY_TO_TIMESTAMP_NTZ` (never a
  bare `::NUMBER` / `::TIMESTAMP_NTZ`) so one bad row does not fail a whole task
  run or an all-or-nothing Dynamic Table refresh.

## Object Naming
- Tasks: `<schema>.<verb>_<noun>` (e.g. `load_transactions_clean`, `build_daily_revenue`)
- Streams: `<schema>.<noun>_stream` (e.g. `new_txn_stream`)
- Dynamic Tables: `<schema>.<noun>_dt` (e.g. `transactions_clean_dt`, `merchant_daily_revenue_dt`)
- Finalizers: `<schema>.pipeline_finalizer`
- Flex tasks: append `_flex` suffix

## Don'ts
- Never leave tasks running after finishing the exercises. Run `chapter9_teardown.sql`.
- Never skip the teardown. Serverless tasks and Dynamic Tables consume credits
  continuously while active.
- Never mix imperative task writes with Dynamic Table ownership on the same table.
- Never consume a stream outside a transaction when the load targets multiple tables.
- Never create a stream without knowing what task or statement will consume it.

Consider these rules if they affect your changes.
