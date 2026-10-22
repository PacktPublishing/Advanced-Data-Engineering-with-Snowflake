# How To Migrate Spark Workloads to Snowpark (Chapter 8)

This chapter rehosts PySpark and Spark SQL jobs onto Snowflake using Snowpark
Connect for Spark, runs them as batch workloads through Snowpark Submit,
redirects cloud data access onto stages and external tables, optimizes the
migrated jobs, and uses Snowflake CoCo to translate the bulk of the estate. Use
this folder to set up the client, run TechFlow's candidate first-wave settlement job end
to end, and prove output parity before retiring anything.

## Prerequisites

- Completed earlier chapters so the following exist:
  - `gold_db.transactions.fact_transactions` (Chapters 4 to 5)
  - `gold_db.customers.dim_customers` (Chapter 7)
  - `@lake_stage` external stage and its storage integration (Chapter 3)
  - `BOOK_WH` warehouse from `setup/snowflake_setup.sql`
- **Python 3.11 recommended**, with `pip` and `venv`; Python 3.12 is an alternative with the conditional compatibility pin in `requirements.txt`. Python 3.10 reaches end of life in October 2026. These Snowpark packages do **not** support Python 3.13.
- A Snowflake role (`TECHFLOW_ETL` in the examples) with `USAGE` on `gold_db`, its schemas, and `BOOK_WH`; `CREATE SERVICE` on the job schema; and `USAGE` on an SPCS compute pool. The Snowpark Submit lab includes the `CREATE COMPUTE POOL` statement an admin runs if no pool exists (`CPU_X64_XS` is enough).
- The Snowflake CLI (`snow`) 3.x, and CoCo installed and authenticated in [Chapter 6](../chapter6/README.md).
- A configured `spark-connect` connection profile in `~/.snowflake/config.toml`. See [`config.toml.example`](config.toml.example).
- An existing Spark environment is useful for the parity exercises but not required.

## Folder Layout

| Path | Purpose |
|------|---------|
| `requirements.txt` | `snowpark-connect[jdk]`, `snowpark-submit`, `pyspark` 3.5.x |
| `config.toml.example` | Sample `~/.snowflake/config.toml` `spark-connect` profile |
| `chapter8_setup.sql` | One-time setup: compute pool, grants, Avro external table, target table (Sections 3.1, 4.2) |
| `AGENTS.md` | CoCo project rules for the migration |
| `migration_tracker_template.csv` | Sections 2.1 and 2.4, provisional waves and dependency evidence |
| `jobs/daily_settlement.py` | Section 3.1, the first-wave PySpark job Snowpark Submit runs (pure PySpark, no Snowflake imports) |
| `snowpark_connect/session.py` | `init_session()` helper for the interactive demos |
| `snowpark_connect/smoke_test.py` | Section 1.3, environment smoke test against `fact_transactions` |
| `snowpark_connect/type_coercion_demo.py` | Section 2.2, `NullType` to `StringType` coercion demo |
| `snowpark_connect/external_stage_io.py` | Section 4.1, stage read/write replacing `s3a://` |
| `snowpark_connect/external_table_read.py` | Section 4.2, reading Avro through an external table |
| `snowpark_connect/jdbc_source.py` | Section 4.3, JDBC read against a sidecar PostgreSQL |
| `snowpark_connect/iceberg_write.py` | Section 4.4, Iceberg write with the external volume set |
| `snowpark_connect/amount_band.py` | Section 5.2, UDF replaced by a pushdown `CASE` |
| `parity/parity_signature.py` | Section 6.4, the type-normalizing parity harness |
| `orchestration/airflow_daily_settlement.py` | Section 3.3, the `BashOperator` task |
| `sql/verify_settlement.sql` | Section 3.2, post-run verification query |
| `commands/` | Shell helpers for setup, submit, and status |
| `prompts/` | CoCo prompts for inventory, read, translate, and submit scaffolding |
| `coco-skills/pyspark-to-snowpark-translator/` | The chapter's headline CoCo skill |

## Steps

1. Bootstrap the environment (Section 1.3, step 1; Section 3.1, step 1).

   ```bash
   ./commands/snowpark_setup.sh
   ```

   This defaults to `python3.11`, creates `.venv`, installs the chapter packages,
   runs `pip check`,
   and copies `config.toml.example` to `~/.snowflake/config.toml` if absent.
   To select the alternative interpreter, run `CHAPTER8_PYTHON=python3.12 ./commands/snowpark_setup.sh`.
   If an existing `.venv` uses a different minor version, move it aside before
   rerunning setup; the script reports the mismatch without replacing it.

2. Add and test the `spark-connect` connection (Section 1.3, step 2).

   ```bash
   snow connection add        # name it spark-connect, point at gold_db / transactions / BOOK_WH
   snow connection test --connection spark-connect
   ```

3. Run the one-time SQL setup (Sections 3.1, 4.2).

   ```bash
   snow sql -c spark-connect -f chapter8_setup.sql
   ```

   Creates `TECHFLOW_SPARK_POOL`, grants the five privileges the submit needs,
   and defines the `ext_payment_events` Avro external table.

4. Smoke-test the development environment (Section 1.3, step 3).

   ```bash
   python -m snowpark_connect.smoke_test
   ```

   The count and the aggregation both appear in Snowsight's query history under
   your role. That is the verification the plan reached Snowflake.

5. Submit the first-wave settlement job and check it (Section 3.2).

   ```bash
   ./commands/submit_daily_settlement.sh                      # prints the suffixed workload name + Job History URL
   ./commands/workload_status.sh DAILY_SETTLEMENT_<suffix>    # status + logs
   snow sql -c spark-connect -f sql/verify_settlement.sql     # confirm the output
   ```

6. Explore the data-access and optimization snippets (Sections 4 and 5).

   ```bash
   python -m snowpark_connect.external_stage_io
   python -m snowpark_connect.external_table_read
   python -m snowpark_connect.amount_band          # explain() shows the CASE pushing down
   ```

7. Accelerate the middle wave with CoCo (Section 6).

   Install the skill once, then run the prompts:

   ```bash
   cp -R coco-skills/* ~/.snowflake/cortex/skills/ && coco   # then /skill sync, /skill list
   ```

   The prompts in `prompts/` cover inventory (`2.1`), per-job read (`6.1`),
   translation (`6.2`), and submit scaffolding (`6.3`).

8. Prove parity and dependency readiness before retiring the Spark job (Sections 2.4 and 6.4).

   Run both versions on the same fixed inputs with separate validation outputs.
   Keep one writer responsible for the published result. The settlement lab
   overwrites its target table; adapt the target before running parallel copies.

   ```python
   from parity.parity_signature import parity_signature
   spark_sig = parity_signature(spark_df,   cols, money_cols={"amount_usd"})
   snow_sig  = parity_signature(snowpark_df, cols, money_cols={"amount_usd"})
   assert spark_sig == snow_sig
   ```

## Migration tracker and dependency checks

The supplied rows illustrate migration choices. Only `daily_settlement.py` is
shipped as a runnable job; the other job names represent reader-supplied work.
The settlement task wrapper does not establish a complete pipeline dependency
graph. Every row therefore starts with `wave=pending` and
`dependency_status=unknown`, including the settlement candidate.

| Field | Meaning |
|---|---|
| `candidate_wave` | Provisional effort-based grouping; does not permit cutover. |
| `wave` | Confirmed migration wave; keep `pending` until dependencies are verified. |
| `upstream_jobs`, `downstream_consumers` | Producer job IDs and consumers of the output; use `none` only when verified. |
| `input_batch`, `readiness_signal` | Required business-date slice or partition and its completion signal. |
| `interface_contract` | Schema, freshness, location, and overwrite/append agreement across the boundary. |
| `dependency_owner`, `dependency_evidence` | Owner who confirms the relationship and the file/task/schedule or confirmation supporting it. |
| `dependency_status` | `unknown`, `blocked`, or `ready`; API compatibility alone cannot make it `ready`. |
| `cutover_group` | Jobs that must switch together when an interface cannot be preserved. |
| `published_output_owner` | The one job responsible for publishing the output during comparison and cutover. |

Use `prompts/inventory_scan.prompt.txt` with the job code and available
orchestration definitions, then confirm the findings with the dependency
owners. Missing code is not evidence that a job is independent. A verified
wave assignment still needs output parity, an affected-chain run, downstream
acceptance, and a rollback route before cutover.

These illustrative cases describe how to make the decision; they are not
claims about the shipped sample's dependencies:

| Case | Wave decision | Publication and retirement rule |
|---|---|---|
| Independent job with verified fixed inputs and a supported output | May enter the first wave after independence is evidenced. | Compare separate outputs; keep one published-output writer. |
| Migrated consumer whose producer remains on Spark | May move if the input contract and batch-completion signal are verified and downstream readers remain compatible. | Keep the Spark producer scheduled; retain a rollback route. |
| Input interface changes or readiness evidence is missing | Keep the wave pending; either defer the job or define and verify a group cutover. | Do not switch publication or retire a required producer. |

## Expected Results

- `snowpark_setup.sh` ends with `snowpark-submit OK` and the next-step hints.
- `smoke_test.py` prints the transaction count and five `(merchant_id, count)` rows, all visible in Snowsight query history.
- `type_coercion_demo.py` prints `null_col: string (StringType)`, not `void (NullType)`: the Section 2.2 coercion in one line.
- `submit_daily_settlement.sh` prints a suffixed workload name like `DAILY_SETTLEMENT_260610_213045` and a Job History URL, and the job reaches `SUCCEEDED`.
- `verify_settlement.sql` returns seven rows of plausible daily settled totals.
- `amount_band.py` `explain()` shows the `CASE` expression in the pushed-down SQL with no UDF node.
- `parity_signature` returns the same `(checksum, row_count)` tuple for the Spark and Snowpark outputs on the same 1% sample.

## Validation on 13 September 2026

A fresh macOS arm64 environment passed installation, `python -m pip check`,
imports of Snowpark Connect and the PySpark Connect client, and
`snowpark-submit -h` with these versions:

| Component | Tested version |
|---|---|
| Python | 3.11.15 |
| snowpark-connect | 1.41.0 |
| snowpark-submit | 1.41.0 |
| pyspark | 3.5.9 |
| snowflake-snowpark-python | 1.54.0 |
| snowflake-connector-python | 4.7.3 |
| jdk4py | 17.0.9.2 |

The setup helper also passed shell syntax checks and rejected a missing
interpreter, Python 3.13, and an existing environment with a different minor
version without replacing that environment. The tracker and manuscript
inventory prompt were checked together. This validation did not start a
Snowflake session or rerun migration workloads; Python 3.12 retains the
previous environment guidance and was not freshly installed in this pass.

## Troubleshooting

- **`snowpark-submit` dies minutes into the run with an infrastructure-looking error.** Almost always a missing grant. Run `chapter8_setup.sql` so the role holds all five privileges (`USAGE` on db/schema/warehouse/compute pool, `CREATE SERVICE`, stage `READ`) before the first submit.
- **Status lookup returns nothing.** Use the suffixed workload name the submit printed (`DAILY_SETTLEMENT_<timestamp>`), not the base name.
- **Logs are gone a few minutes after the run.** Default retention is short. Route logs to the `gold_db.telemetry.techflow_events` event table from Chapter 7.
- **A naive schema diff fails on a correct migration.** Integer types come back as `LongType` and `lit(None)` as `StringType`. Normalize types with `parity/parity_signature.py` before comparing.
- **`spark.read.format("avro")` fails.** Avro and ORC are not in the read path. Read the `ext_payment_events` external table instead (Section 4.2).
- **`Append`/`Ignore` write fails.** Those modes are unsupported on file writes. Write to a Snowflake table or restructure to a dated overwrite path.
- **JDBC read raises a driver-not-found error.** The driver JAR must be on the translation layer's classpath; locally that is an env var, in Notebooks an uploaded JAR plus an external access integration.
- **Iceberg write fails on a Snowflake-managed table.** Set `snowpark.connect.iceberg.external_volume` in session config (see `iceberg_write.py`) or link it as a database default. Table creation through Spark SQL is not supported.
- **Python version errors.** Use `python3.11` by default, or select `python3.12` with `CHAPTER8_PYTHON`. The script rejects unsupported interpreters and existing environments with a different minor version.

## Additional Information

- **Schema binding.** The chapter prose uses illustrative column names (`amount_usd`, `settled_at`) and a `'SETTLED'` status. The runnable scripts here are bound to the actual companion `gold_db.transactions.fact_transactions` from Chapters 4 to 5: source columns `AMOUNT` and `TRANSACTION_TS`, and status `'COMPLETED'`. Output column names (`settled_amount_usd`, `settled_txn_count`) are kept as the chapter shows them. The settlement aggregation was verified live against the companion data.
- **`@lake_stage` is a Chapter 3 artifact** and is not created by `chapter8_setup.sql`. If your account only has the Chapter 7 `UDF_STAGE` / `SPROC_STAGE`, run [`sql/external_stage_setup.sql`](sql/external_stage_setup.sql) first (substitute the `<REPLACE: ...>` placeholders with your bucket and IAM role), or the external table and the `external_stage_io.py` / `external_table_read.py` demos will fail with "stage does not exist".
- The companion CoCo skill in [`coco-skills/pyspark-to-snowpark-translator/`](coco-skills/pyspark-to-snowpark-translator/SKILL.md) encodes the Section 2.2 gaps and the Section 5.1 cleanup list, so the `prompts/translate_pyspark.prompt.txt` prompt flags incompatibilities instead of silently translating around them.
- `jobs/merchant_rollup.py` referenced by the translate and submit prompts is a reader-supplied middle-wave job; the chapter does not ship its source. Point the prompts at any of your own PySpark jobs.
- The cost numbers in Section 5.4 use illustrative rates ($0.48/node-hour EMR, $3.00/credit Snowflake). Substitute contract rates before sharing the comparison.
- Chapter 9 (`Native Orchestration with Tasks, DAGs, and Dynamic Tables`) covers the workloads that belong inside Snowflake's own scheduling machinery, which the rehosted Spark jobs deliberately kept external.
