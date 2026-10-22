# task-dag-author

A CoCo skill for generating Snowflake task graphs, streams, triggered tasks,
and Dynamic Table chains following the patterns established in Chapter 9.

## When to use

Use this skill when prompted to build native orchestration for a Snowflake
pipeline: task graphs with AFTER chains, streams with triggered tasks, or
Dynamic Table chains with lag tuning. The skill encodes the Chapter 9 design
rules so generated code follows best practices by default.

## Design rules encoded

1. **One writer per table.** Never point a scheduled task and a Dynamic Table
   at the same target. If a table is a Dynamic Table, every value comes from
   its SELECT.
2. **Explicit refresh mode.** Set `REFRESH_MODE = INCREMENTAL` (or `FULL`)
   explicitly on every Dynamic Table. Never rely on AUTO for production.
3. **DOWNSTREAM lag on intermediates.** Intermediate Dynamic Tables in a chain
   use `TARGET_LAG = 'DOWNSTREAM'` so they refresh only as often as their most
   demanding consumer requires.
4. **Stream guard on triggered tasks.** Every triggered task that consumes a
   stream includes `WHEN SYSTEM$STREAM_HAS_DATA(...)` to prevent empty runs.
5. **Failure controls on scheduled roots.** Every scheduled root task sets
   `SUSPEND_TASK_AFTER_NUM_FAILURES` (default 3) and
   `TASK_AUTO_RETRY_ATTEMPTS` (default 2).
6. **Finalizer for audit.** Every task graph includes a finalizer that logs the
   run outcome to an audit table.
7. **Consume streams atomically.** When a stream feeds multiple targets, wrap
   the writes in an explicit transaction so the offset advances only on commit.

## Five-point review checklist

Before running any generated code, confirm:

1. The `WHEN SYSTEM$STREAM_HAS_DATA` guard is present on every triggered task.
2. Intermediate Dynamic Table lags are set to `DOWNSTREAM`.
3. `REFRESH_MODE` is set explicitly (not AUTO) on every Dynamic Table.
4. A single writer owns each table (no mixed task + DT ownership).
5. `SUSPEND_TASK_AFTER_NUM_FAILURES` is set on every scheduled root.

## Example prompt

> Using the task-dag-author skill, build a task graph that cleanses
> `raw_db.streaming.raw_transactions` into
> `silver_db.transactions.transactions_clean`, then aggregates a daily
> merchant revenue fact in `gold_db`, with two automatic retries, a failure
> threshold, and a finalizer that logs each run.

## Limitations

This skill generates DDL for review. It does not execute statements. Always
review generated code against the five-point checklist before running.
