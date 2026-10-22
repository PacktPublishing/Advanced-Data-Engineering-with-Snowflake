# How To Review the TechFlow Dagster Project

This project implements the Chapter 11 Dagster examples as a components-ready
asset graph. It combines four handwritten Snowflake assets with a declarative dbt
component and triggers the complete graph from an S3 sensor (`scores_sensor`);
`schedules.py` holds the time-driven alternative.

## Prerequisites

- Python 3.11 or later
- The dependencies declared in `pyproject.toml`
- A Snowflake service user with the Chapter 11 `TRANSFORMER_RL` privileges
- An unencrypted PKCS#8 private key file (the same file every tool loads)
- The single shared dbt project at `../../chapter6/dbt/techflow_warehouse`; copy
  its `profiles.yml.example` to `profiles.yml` and run `dbt deps` in it once

## Steps

1. Copy `.env.example` to `.env`.
2. Replace every placeholder with the Snowflake service user's values. The key is
   unencrypted, so no passphrase variable is needed.
3. Store `SNOWFLAKE_PRIVATE_KEY_PATH` (and the key file) in a secrets manager in
   deployed environments. Never commit `.env` or the key file.
4. Review `commands/scaffold_dbt_component.sh` without arguments. Its default
   mode only prints the exact `dg scaffold defs` command; `--apply` is
   intentionally required before it can write files.
5. Review the component in
   `src/techflow_orchestration/defs/techflow_dbt/defs.yaml`. Its project path
   resolves from `context.project_root` to the shared Chapter 6 project, and it
   selects only `tag:nightly`.
6. Review the dbt source metadata in
   `../../chapter6/dbt/techflow_warehouse/models/gold/_chapter11_sources.yml`.
   The source asset key is `transactions_clean`, matching the handwritten
   Dagster asset exactly.
7. After dependency installation, use these non-materializing checks:

   ```bash
   dg check toml
   dg check yaml
   dg check defs
   ```

   `dg check defs` may parse the dbt manifest. It does not materialize an
   asset, run `dbt build`, call the cleansing procedure, or execute SQL.

## Expected Results

- `transactions_clean` appears upstream of `merchant_daily_revenue` and the
  dbt-managed `merchant_activity`, and `marketing_segment` sits at the end.
- `scores_sensor` is registered as the graph's trigger (the time-driven
  `ScheduleDefinition` in `schedules.py` is the alternative).
- The Snowflake resource reports its required `SNOWFLAKE_*` environment
  variables without exposing their values.

## Troubleshooting

- **Component path not found:** Run checks from this `dagster` directory and
  confirm `../../chapter6/dbt/techflow_warehouse/dbt_project.yml` exists.
- **dbt profile error:** Copy `profiles.yml.example` to `profiles.yml` in the
  shared Chapter 6 project; the component validates a `profiles.yml` in that dir.
- **Missing source edge:** Keep
  `config.meta.dagster.asset_key: ["transactions_clean"]` on the dbt source and
  use `source('transactions', 'transactions_clean')` in the model.
- **Duplicate asset key:** Do not rename the dbt model to
  `merchant_daily_revenue`; that key already belongs to the handwritten asset.

## Additional Information

`merchant_daily_revenue` intentionally preserves the manuscript's full-table
`INSERT OVERWRITE`. It executes only when that asset is materialized. Static
validation, Python parsing, TOML/YAML checks, and dbt manifest parsing do not
execute the statement. Review the SQL and its full-table scope before enabling
the schedule or materializing assets.
