# How To Run Chapter 7 (Snowpark Python for Data Engineering)

This chapter moves transformation work into Python while keeping every byte of data inside Snowflake. Use this folder to install Snowpark, deploy the example UDFs, UDTFs, and stored procedures, and run the local testing framework that gates the companion CI pipeline.

## Prerequisites

- Completed [Chapter 4](../chapter4/README.md) and [Chapter 5](../chapter5/README.md) so the following objects exist:
  - `gold_db.transactions.fact_transactions` (Chapter 5, Section 1.1, `chapter5_1_window_functions.sql`)
  - `silver_db.customers.silver_customers` (Chapter 6) or `raw_db.crm.customer` (Chapter 5, Section 3.1)
  - `BOOK_WH` warehouse from `setup/snowflake_setup.sql`
- **Python 3.11** with `pip` and `venv` (as of August 2026, Snowpark supports Python 3.10 to 3.13, with 3.9 deprecated; the examples pin 3.11).
- A Snowflake role with `CREATE FUNCTION`, `CREATE PROCEDURE`, `CREATE STAGE`, and `USAGE` on `gold_db` and `silver_db`.
- **Snowflake Edition**: Standard or higher. Snowpark-optimized warehouses are available in every edition; the default memory configuration requires a minimum size of **MEDIUM** (X-Small is rejected for the `SNOWPARK-OPTIMIZED` type), and it bills at a higher credit rate, so suspend it when the `benchmark_udfs.py` runs finish.
- A configured Snowflake CLI connection in `~/.snowflake/config.toml`. See [`config.toml.example`](config.toml.example) for the template the examples expect, with a `default` connection profile.

## Folder Layout

| Path | Purpose |
|------|---------|
| `requirements.txt` | Python packages (`snowflake-snowpark-python[modin]`, snowflake-ml-python, pytest) |
| `config.toml.example` | Sample `~/.snowflake/config.toml` entry the examples resolve via `connection_name` |
| `chapter7_setup.sql` | One-time setup: UDF/sproc stages, `control.batch_log`, `staging.customer_batch` |
| `AGENTS.md` | Cortex Code project rules used by the prompts in `prompts/` |
| `snowpark/session.py` | Reusable `build_session()` helper used by every script in the chapter |
| `snowpark/dataframe_api/` | Section 1, DataFrame API, pushdown, `explain()`, and the pure-Snowpark vs. early-`to_pandas` benchmark |
| `snowpark/pandas_on_snowflake/` | Section 2, `modin.pandas` on Snowflake and the fallback warning demo |
| `snowpark/udfs/` | Section 3, scalar and vectorized UDFs, plus the 200M-row benchmark harness |
| `snowpark/udtfs/` | Section 4.1, velocity-burst UDTF with `partition_by` / `order_by` |
| `snowpark/sprocs/` | Section 4.2, `promote_customer_batch` stored procedure |
| `snowpark/ml/` | Section 4.3, Snowpark ML Feature Store and Model Registry sketch |
| `tests/conftest.py` | Section 5.1, `local_session` pytest fixture (in-memory engine) |
| `tests/unit/` | Section 5.1 and 5.2, DataFrame and UDF unit tests, no warehouse |
| `tests/integration/` | Warehouse-backed smoke tests (gated by `SNOWFLAKE_CONNECTION_NAME`) |
| `ci/github-actions-snowpark.yml` | Section 5.3, two-tier CI pipeline (unit on push, integration on PR) |
| `commands/` | Shell helpers for setup, deploy, run, and test |
| `prompts/` | Cortex Code prompts that pair with this chapter |

## Steps

1. Create and activate a Python virtual environment from this folder.

   ```bash
   python3.11 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. Configure your Snowflake CLI connection.

   Copy `config.toml.example` to `~/.snowflake/config.toml` (or merge the `default` profile into your existing file). Export `SF_PASSWORD` or use key-pair auth, the file references both options.

   ```bash
   mkdir -p ~/.snowflake
   cp config.toml.example ~/.snowflake/config.toml   # or merge by hand
   chmod 600 ~/.snowflake/config.toml
   ```

3. Run the one-time SQL setup from a Snowsight worksheet (or `snow sql -f`).

   ```bash
   snow sql -c default -f chapter7_setup.sql
   ```

   This creates the `udf_stage` and `sproc_stage` internal stages, the `control.batch_log` table, and a small `staging.customer_batch` seed used by the stored procedure example.

4. Smoke-test the session helper and the DataFrame examples.

   ```bash
   python -m snowpark.session                              # prints session.sql_id and active context
   python -m snowpark.dataframe_api.monthly_revenue        # Section 1.2
   python -m snowpark.dataframe_api.explain_plan           # Section 1.3
   ```

5. Run the pandas-on-Snowflake demo and watch the fallback warning.

   ```bash
   python -m snowpark.pandas_on_snowflake.read_snowflake_demo   # Section 2.1
   python -m snowpark.pandas_on_snowflake.fallback_demo         # Section 2.2, expect MODIN_DEFAULTING_TO_LOCAL_EXECUTION
   ```

6. Deploy the UDF, UDTF, and stored procedure to Snowflake.

   ```bash
   ./commands/deploy_udfs.sh
   ```

   The script imports each module so the `@udf`, `@pandas_udf`, `udtf(...)`, and `@sproc` decorators register the objects under `gold_db.public`. Re-running is safe, every registration uses `replace=True`.

7. Call the deployed objects from SQL to verify.

   ```sql
   USE ROLE TRANSFORMER_ROLE; USE WAREHOUSE BOOK_WH;

   SELECT classify_risk_tier(85.0::FLOAT, 250.0::FLOAT);
   SELECT classify_risk_tier_vec(85.0::FLOAT, 250.0::FLOAT);

   CALL promote_customer_batch('2026-04-29-batch-0001');
   SELECT * FROM gold_db.control.batch_log ORDER BY logged_at DESC LIMIT 5;
   ```

8. Run the local unit tests (no warehouse, no credits).

   ```bash
   pytest -q tests/unit
   ```

9. Run the warehouse-backed integration tests.

   ```bash
   export SNOWFLAKE_CONNECTION_NAME=default
   pytest -q tests/integration
   ```

## Expected Results

- `snowpark.session` prints a single line ending in `OK`, with the active database, schema, and warehouse.
- `monthly_revenue.py` prints 10 rows of `(merchant_id, revenue_month, monthly_revenue)` sorted by merchant and month, and `explain()` produces a single `SELECT … GROUP BY … ORDER BY` SQL plan with no `LocalRelation` nodes.
- `read_snowflake_demo.py` returns 10 rows in under a second against a small fact-transactions sample without copying the table to the laptop.
- `fallback_demo.py` emits a `MODIN_DEFAULTING_TO_LOCAL_EXECUTION` warning on `.corr()` once the column count or row count crosses the fallback boundary.
- After `deploy_udfs.sh`, `SHOW USER FUNCTIONS IN SCHEMA gold_db.public` lists `classify_risk_tier`, `classify_risk_tier_vec`, and `flag_velocity_bursts`. `SHOW PROCEDURES` lists `promote_customer_batch`.
- `pytest -q tests/unit` reports `15 passed` in well under a second, with no Snowflake credits consumed.
- `pytest -q tests/integration` runs against `BOOK_WH`, calls each deployed object, and tears the smoke rows down on exit.

## Troubleshooting

- If `SnowparkSQLException: 002003: Object 'GOLD_DB.PUBLIC.UDF_STAGE' does not exist` appears, run `chapter7_setup.sql` before `deploy_udfs.sh`.
- If `MODIN_DEFAULTING_TO_LOCAL_EXECUTION` fires unexpectedly, narrow the input with a filter that pushes down (e.g., `transactions[transactions['STATUS'] == 'COMPLETED']`) or rewrite the hot path in Snowpark DataFrames. Section 2.3 of the chapter gives the decision rule.
- If `SnowparkPandasUnsupportedOperationException: corr() with > N columns` appears, the input frame is too wide for that operation to push down. Section 2.2 reproduces this case deliberately.
- If a vectorized UDF returns `None` for every row, make sure the function returns a `pd.Series`, not a list. Wrap `np.select(...)` in `pd.Series(...)` as `snowpark/udfs/vectorized_risk_tier.py` does.
- If `promote_customer_batch` returns `EMPTY`, load the staging seed first with `snow sql -c default -f chapter7_setup.sql`.
- If pytest fails with `Session.builder requires local_testing`, install `snowflake-snowpark-python>=1.20.0`. Earlier releases shipped a stub.
- If `pd.read_snowflake` raises `ImportError: Please refer to installation documentation page to install an engine`, the Snowflake backend was never registered with Modin. Add `import snowflake.snowpark.modin.plugin` before `import modin.pandas as pd`, and install the engine via `snowflake-snowpark-python[modin]` (the bare `modin` package no longer auto-discovers it on 0.37+).
- If a DataFrame chain raises `TypeError: 'DATEADD' expected Column or str, got: <class 'int'>`, wrap integer arguments with `lit(...)` — e.g. `dateadd("day", lit(-90), current_date())`. snowflake-snowpark-python 1.51+ rejects bare Python ints in `dateadd`.
- If the Snowpark-optimized warehouse `CREATE` fails with `000676: X-Small warehouse size is not supported for SNOWPARK-OPTIMIZED warehouse type`, use `WAREHOUSE_SIZE = 'MEDIUM'` (the current minimum size for that type); `chapter7_setup.sql` already does.
- If Modin import errors appear on Apple Silicon, build the virtualenv with `python3.11`/`python3.12` rather than the Homebrew system Python.

## Additional Information

- The benchmark numbers in Section 3.2 come from `snowpark/udfs/benchmark_udfs.py`, run on a MEDIUM Snowpark-optimized warehouse. The scalar-vs-vectorized gap depends on the logic: for cheap row-wise rules the scalar UDF can win, while vectorized UDFs pay off when per-row Python work is expensive (model inference, regex, JSON parsing). Numbers vary with warehouse size, data shape, and Snowflake release — run the benchmark against your own data before quoting figures.
- The companion Cortex Code project rules live in [`AGENTS.md`](AGENTS.md). When the rules are loaded, the prompts in `prompts/` will produce Snowpark code that follows the chapter conventions.
- Chapter 8 (`Migrating Spark Workloads to Snowpark`) builds on every primitive in this folder. The stored procedure and UDTF shapes here are the same shapes the migration chapter lands PySpark code into.
