# How To Build Native Orchestration with Tasks, Streams, and Dynamic Tables (Chapter 9)

This chapter replaces TechFlow's hand-run transaction pipeline with native
Snowflake orchestration: scheduled and chained tasks, streams and triggered
tasks for reactive processing, and Dynamic Tables for declarative
transformation. Use this folder to run every code block from the chapter end to
end against your book account.

## Prerequisites

- Completed earlier chapters so the following exist:
  - `raw_db.streaming.raw_transactions` VARIANT landing table (Chapter 4)
  - `gold_db.transactions.fact_transactions` (Chapter 5) with seed rows
  - `BOOK_WH` warehouse from `setup/snowflake_setup.sql`
- Administrator access for the one-time data setup and role bootstrap. The
  shared-object setup defaults to `SYSADMIN`; use the existing object owner
  if earlier chapters used another role. The role bootstrap uses `USERADMIN`
  for role creation, `ACCOUNTADMIN` for account grants, and `SECURITYADMIN`
  for membership and object grants.
- `CH09_ORCHESTRATOR` for every exercise. `CREATE TASK` is a schema privilege;
  `EXECUTE TASK` and `EXECUTE MANAGED TASK` are account privileges. The bootstrap
  also grants access to the warehouse, databases, schemas, source and target
  tables, and cleansing procedure. Normal task execution does not require
  `ACCOUNTADMIN`. Each SQL file selects the role and disables secondary roles.
- Snowflake CLI (`snow`) 3.0+ or Snowsight for running the scripts.

## Folder Layout

| Path | Purpose |
|------|---------|
| `chapter9_setup.sql` | One-time setup: databases (incl. `ops_db`), schemas, silver/gold tables, `ops_db.pipelines.pipeline_run_log`, seed data from `fact_transactions`, `ops_db.pipelines.run_cleanse()` proc |
| `chapter9_admin_setup.sql` | One-time role creation, account and object grants, role verification; run after data setup |
| `AGENTS.md` | Project rules for the native orchestration chapter |
| `sql/01_scheduled_task.sql` | Section 1.1: create, resume, execute the cleansing task + `task_history` |
| `sql/02_task_graph.sql` | Section 1.2: `build_daily_revenue` AFTER chain + `SYSTEM$TASK_DEPENDENTS_ENABLE` |
| `sql/03_retries_finalizer.sql` | Section 1.3: retry/suspend ALTER, finalizer task, Serverless Tasks Flex |
| `sql/04_streams.sql` | Section 2.1: `new_txn_stream` on the landing table + inspect query |
| `sql/05_triggered_task.sql` | Section 2.2: `process_new_transactions` with WHEN guard + resume |
| `sql/06_stream_incremental_txn.sql` | Section 2.3: explicit BEGIN/COMMIT multi-target stream load |
| `sql/07_dynamic_table.sql` | Section 3.1: `transactions_clean_dt` with TARGET_LAG |
| `sql/08_refresh_mode.sql` | Section 3.2: Inspect the AUTO result for the silver table from script 07 (run before 09) |
| `sql/09_dt_chain_downstream.sql` | Section 3.3: `merchant_daily_revenue_dt` + DOWNSTREAM ALTER |
| `sql/10_monitoring.sql` | Section 4.3: failed-task history + refresh history with `completion_target` |
| `chapter9_pipeline.sql` | Section 4.2: end-to-end pipeline topology (one writer per table) |
| `chapter9_teardown.sql` | Suspend and drop all tasks, streams, and Dynamic Tables |
| `coco-skills/task-dag-author/SKILL.md` | CoCo skill stub referenced in Section 5.3 |

## Steps

1. Run the one-time data setup as the shared objects' owner, then the administrator bootstrap.

   ```bash
   snow sql -f chapter9_setup.sql
   snow sql -f chapter9_admin_setup.sql
   ```

   Creates the `ops_db.pipelines`, `silver_db.transactions`, and
   `gold_db.transactions` objects, seeds the VARIANT landing table with recent
   timestamps from `fact_transactions`, and registers the
   `ops_db.pipelines.run_cleanse()` stored procedure. The data setup enables
   change tracking on the raw source using its owner role. The administrator
   bootstrap then assigns `CH09_ORCHESTRATOR` to the user running it and grants
   the runtime privileges. Expect the final context query to show that role
   with secondary roles disabled. An administrator can grant the same role to
   another authorized reader separately.

2. Walk through the section scripts in order.

   ```bash
   snow sql -f sql/01_scheduled_task.sql
   snow sql -f sql/02_task_graph.sql
   snow sql -f sql/03_retries_finalizer.sql
   snow sql -f sql/04_streams.sql
   snow sql -f sql/05_triggered_task.sql
   snow sql -f sql/06_stream_incremental_txn.sql
   snow sql -f sql/07_dynamic_table.sql
   snow sql -f sql/08_refresh_mode.sql
   snow sql -f sql/09_dt_chain_downstream.sql
   snow sql -f sql/10_monitoring.sql
   ```

   Each file is self-contained and maps to one section of the chapter. Run them
   in order because later scripts depend on objects created by earlier ones.
   Script 07 creates `transactions_clean_dt` with AUTO. Script 08 inspects
   that silver table before script 09 creates the gold table with explicit
   INCREMENTAL. The silver table's configured mode remains AUTO; SHOW reports
   the mode Snowflake resolved. ADAPTIVE is generally available. The chapter
   discusses CUSTOM_INCREMENTAL separately; this folder does not add a custom
   refresh lab.

3. (Optional) Build the full end-to-end pipeline topology.

   ```bash
   snow sql -f chapter9_pipeline.sql
   ```

4. Tear down all chapter objects when finished.

   ```bash
   snow sql -f chapter9_teardown.sql
   ```

   This suspends and drops every task, stream, and Dynamic Table created by the
   chapter scripts. **Do not skip this step** — active serverless tasks and
   Dynamic Tables consume credits continuously.

## Expected Results

- `chapter9_setup.sql` seeds the landing table with rows whose timestamps fall
  within the last 36 hours, so the nightly window filter picks them up.
- `01_scheduled_task.sql`: `task_history` shows `SUCCEEDED` for `LOAD_TRANSACTIONS_CLEAN`
  and `transactions_clean` contains cleansed rows.
- `02_task_graph.sql`: `merchant_daily_revenue` is populated after the graph runs.
- `03_retries_finalizer.sql`: `ops_db.pipelines.pipeline_run_log` has a row from
  the finalizer. The Flex task compiles (may not execute if the account lacks
  serverless support).
- `04_streams.sql`: the stream query returns zero rows (stream starts empty with
  `SHOW_INITIAL_ROWS = FALSE`).
- `05_triggered_task.sql`: after inserting fresh rows into the landing table,
  the triggered task fires and merges them into `transactions_clean`.
- `07_dynamic_table.sql`: `transactions_clean_dt` populates on its first refresh.
- `09_dt_chain_downstream.sql`: `merchant_daily_revenue_dt` populates and the
  silver DT is retuned to `DOWNSTREAM`.
- `08_refresh_mode.sql`: `SHOW DYNAMIC TABLES` returns `refresh_mode = INCREMENTAL`
  with a `NULL` `refresh_mode_reason` for `transactions_clean_dt`.
- `10_monitoring.sql`: monitoring queries return results (possibly zero failed
  tasks if everything succeeded); the refresh-history query shows
  `completion_target` and `seconds_behind_target`.

## Troubleshooting

- **`EXECUTE TASK` returns but `task_history` shows nothing.** Tasks run
  asynchronously. Wait 10-30 seconds and re-query `task_history`.
- **Task shows `FAILED` with a privilege error.** Verify `CURRENT_ROLE()` and
  `SHOW GRANTS TO ROLE CH09_ORCHESTRATOR`. The task owner needs account-level
  `EXECUTE TASK`, plus `EXECUTE MANAGED TASK` for serverless compute and access
  to the objects used by its body. A caller using another role needs OWNERSHIP
  or OPERATE on the task; execution still uses the task owner's privileges.
  Granting only `CREATE TASK` does not permit a run.
- **Flex task (`TARGET_COMPLETION_INTERVAL`) fails.** Serverless Tasks Flex may
  be edition- or region-gated. The task is included for completeness; skip it
  if your account does not support it.
- **`Cannot have predecessor ... from a different schema`.** All tasks in a
  graph must live in one schema. This is why every task lives in
  `ops_db.pipelines` and writes cross-database with fully qualified names.
- **`08_refresh_mode.sql` returns no rows.** It inspects
  `silver_db.transactions.transactions_clean_dt`. Run script 07 first and
  check that the role can see the silver schema and table.
- **Stream goes stale.** If you wait too long between creating the stream and
  consuming it, the offset can fall out of retention. Recreate the stream.
- **Dynamic Table refresh shows FULL instead of INCREMENTAL.** Check whether
  the query uses constructs that prevent incremental refresh (window functions,
  non-deterministic functions in the SELECT list).
- **Credits burning after the exercises.** Run `chapter9_teardown.sql`
  immediately. Verify with `SHOW TASKS` and `SHOW DYNAMIC TABLES` that nothing
  is left running.

## Schema Binding

The chapter scripts use the real companion objects verbatim:

| Chapter reference | Companion object |
|-------------------|-----------------|
| `raw_db.streaming.raw_transactions` | Same — VARIANT landing table from Chapter 4 |
| `silver_db.transactions.transactions_clean` | Created by `chapter9_setup.sql` |
| `silver_db.transactions.rejected_transactions` | Created by `chapter9_setup.sql` |
| `ops_db.pipelines.pipeline_run_log` | Created by `chapter9_setup.sql` (finalizer audit log) |
| `ops_db.pipelines.*` (tasks) | Every task in the graph — one schema per graph |
| `gold_db.transactions.merchant_daily_revenue` | Created by `chapter9_setup.sql` |
| `gold_db.transactions.fact_transactions` | Chapter 5 (used as seed source) |
| `BOOK_WH` | Book-wide warehouse from `setup/snowflake_setup.sql` |
| `currency` | Column name matches `fact_transactions.currency` |
| `run_cleanse()` | Stored procedure `ops_db.pipelines.run_cleanse()` (Section 1.3 Flex task) |

The chapter uses `currency` (not `currency_code`) throughout, matching the
`fact_transactions` schema from Chapter 5. The VARIANT landing rows are parsed
with colon-cast notation (`raw_data:transaction_id::STRING`, etc.).

## Design Notes

Three environment realities shaped the pipeline. The chapter prose and this
companion code are in sync on all three.

1. **One schema per task graph (`ops_db.pipelines`).** Snowflake requires every
   task in a graph to share one database and schema, so a cross-schema `AFTER`
   (for example, a `gold_db` child of a `silver_db` root) fails with
   `Cannot have predecessor ... from a different schema`. The whole graph lives
   in `ops_db.pipelines` and its task bodies write cross-database to
   `raw_db` / `silver_db` / `gold_db` with fully qualified names. This is the
   dedicated orchestration schema that Chapter 10 builds on.

2. **Safe casts on the all-or-nothing refresh.** The landing table can hold
   dirty payloads (for example `raw_data:amount = 'N/A'` from earlier chapter
   exercises). A Dynamic Table refresh is all-or-nothing, so a single bad value
   in a bare `::NUMBER(12,2)` cast fails the entire refresh. Every cast of
   `amount` and `timestamp` uses `TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2)`
   and `TRY_TO_TIMESTAMP_NTZ(raw_data:timestamp::STRING)`, turning a bad value
   into a `NULL` instead of a failed run.

3. **Refresh-mode and monitoring APIs.** Refresh mode is inspected with
   `SHOW DYNAMIC TABLES ... ->> SELECT "name","refresh_mode","refresh_mode_reason"`
   rather than `SYSTEM$ESTIMATE_DYNAMIC_TABLE_REFRESH_MODE`, which is not
   available on all editions. Refresh-lag monitoring uses the universally
   available `completion_target` column with
   `DATEDIFF('second', completion_target, refresh_end_time)` instead of
   `target_lag_sec` / `mean_lag_sec`, which are not present on every account
   version.

## Existing objects from an earlier Chapter 9 run

The bootstrap grants access to shared tables without transferring ownership.
Creating the new role does not make it the owner of tasks, streams, or Dynamic
Tables created by a different role. Before rerunning a disposable lab, inspect
`SHOW TASKS IN SCHEMA ops_db.pipelines`, `SHOW STREAMS IN SCHEMA raw_db.streaming`,
and `SHOW DYNAMIC TABLES` in the silver and gold schemas. Keep the tasks suspended
while deciding whether their contents are needed.

For an expendable earlier lab, use a local copy of `chapter9_teardown.sql` with
its `USE ROLE` line set to the old object owner. Review its named objects, then
run it before the new section scripts. It removes Chapter 9 tasks, streams and
Dynamic Tables; it retains the raw, silver and gold ordinary tables. Recreating
a stream loses its previous offset, so do not use this reset for a pipeline with
unprocessed changes. For objects that must be preserved, have their owner plan
an ownership migration instead. The standard scripts do not perform it.

## Monitoring in Workspaces

Open the two queries from `sql/10_monitoring.sql` as SQL files in Snowsight
Workspaces. They use fully qualified history functions, so a connection's
default database does not change which function is called. The task query only
reports visible failed runs in `ops_db.pipelines`, within its history limit.
No rows does not establish that all expected tasks ran. The refresh query
returns up to 50 gold refreshes and compares completion time with the target.
An independent monitoring role needs MONITOR on the Dynamic Tables and access
to their databases and schemas; the exercise role owns its created tables.

For optional combined charts, use Streamlit in Snowflake. These SQL scripts do
not create an app, a legacy Snowsight dashboard, or an automatic refresh schedule.

## September 2026 comment revision validation

The two revised monitoring queries were executed read-only against the book
account on Snowflake 10.32.102 on September 13, 2026. The task query returned no
visible failures; the Dynamic Table query returned 50 refresh-history rows.
Those checks used ACCOUNTADMIN and do not validate the new custom-role grants.
The custom-role, task execution, serverless, and new Dynamic Table sequence
checks require an isolated setup. Automatic approval review blocked that setup;
these runtime checks remain pending. The repository changes must not be described
as a successful custom-role end-to-end run until those checks pass.
