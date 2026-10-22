# How To Run Chapter 6 (Transformation Frameworks)

This chapter turns the SQL from earlier chapters into testable dbt and SQLMesh projects. Use this folder to install the tools, parse the projects, and run the chapter exercises against your Snowflake account.

## Prerequisites

- Completed `setup/snowflake_setup.sql` so `BOOK_WH` exists.
- Completed Chapter 5, or at least these tables populated with sample data:
  - `raw_db.crm.customer`
  - `gold_db.transactions.fact_transactions`
- Python 3.11 or 3.12 with `pip` and `venv`. Python 3.10 reaches end of life in October 2026, and dbt-core 1.10 does not support 3.13.
- `TRANSFORMER_ROLE`, created by `sql/chapter6_setup_role.sql` in this folder. It carries `USAGE` on `BOOK_WH`, read access on `raw_db` and `gold_db`, and `CREATE SCHEMA` on `silver_db` and `gold_db`. Run that script once before the steps below.

## Folder Layout

| Path | Purpose |
|------|---------|
| `requirements.txt` | Python packages used by dbt, SQLMesh, and SQL linting |
| `sql/chapter6_setup_role.sql` | Creates TRANSFORMER_ROLE with least-privilege grants (run first) |
| `dbt/techflow_warehouse/` | Runnable dbt Core project from Section 1 |
| `dbt/techflow_warehouse/AGENTS.md` | CoCo project rules from Section 4.2 |
| `dbt/techflow_warehouse/.cortex/skills/` | CoCo custom skills from Section 4.3 (the `.cortex` path is the CLI's own convention) |
| `dbt/techflow_warehouse/packages.yml` | dbt package dependencies for utility and audit macros |
| `dbt/techflow_warehouse/macros/generate_schema_name.sql` | Uses each model's custom schema verbatim, and suffixes `__ci` on the CI target |
| `dbt/techflow_warehouse/macros/ci/` | CI helper macros for the prod clone and row-count diff |
| `sqlmesh/techflow_sqlmesh/` | Runnable SQLMesh project from Section 2 |
| `commands/` | Shell and PowerShell snippets captured from the chapter |
| `prompts/` | CoCo prompt examples from Section 4 |
| `sql/monitoring_slack_alert.sql` | Review-only daily quality report task and Slack procedure from Section 5.4 |
| `ci/github-actions-ci.yml` | Mirror of `.github/workflows/chapter6-ci.yml` (Section 5.2); CI fails if they drift |

The pull request template from Section 5.1 lives at the repository root in
`.github/PULL_REQUEST_TEMPLATE.md`, where GitHub picks it up.

## Steps

1. Create the chapter role. Run `sql/chapter6_setup_role.sql` in a Snowflake worksheet, substituting your username in the `GRANT ROLE ... TO USER` line. It also sets `TRANSFORMER_ROLE` as your default role, which is what CoCo in Snowsight uses.

2. Create and activate a Python virtual environment from this folder.

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. Configure dbt credentials.

   Copy `dbt/techflow_warehouse/profiles.yml.example` into `~/.dbt/profiles.yml` or merge the `techflow_warehouse` profile into your existing file. Set the `SF_ACCOUNT`, `SF_USER`, `SF_PASSWORD`, and `SF_ROLE` environment variables before running dbt. `SF_ROLE` has no default, so dbt fails with a clear message rather than silently connecting as a privileged role; set it to `TRANSFORMER_ROLE`, not `ACCOUNTADMIN`.

4. Parse and debug the dbt project.

   ```bash
   cd dbt/techflow_warehouse
   dbt deps
   dbt debug
   dbt parse
   dbt compile
   dbt source freshness
   ```

5. Run the dbt build only after reviewing the generated SQL.

   ```bash
   dbt build
   dbt docs generate
   dbt docs serve --port 8080
   ```

   `dbt build` creates or replaces objects in `silver_db.customers` and `gold_db.customers`, so review the compiled SQL under `target/compiled/` before executing it in a shared account.

6. Configure SQLMesh credentials.

   ```bash
   export SF_ACCOUNT='<your-account-locator>'
   export SF_USER='<your-user>'
   export SF_PASSWORD='<your-password>'
   export SF_ROLE='TRANSFORMER_ROLE'
   ```

7. Validate the SQLMesh project metadata.

   ```bash
   cd ../../sqlmesh/techflow_sqlmesh
   sqlmesh info
   ```

8. Run the SQLMesh workflow when you are ready to create dev objects.

   ```bash
   sqlmesh plan dev
   sqlmesh table_diff prod:dev gold_db.customers.gold_customer_value --on customer_id --show-sample
   sqlmesh plan prod
   ```

## Expected Results

- `dbt parse` succeeds and writes a manifest under `dbt/techflow_warehouse/target/`.
- `dbt compile` writes reviewable SQL under `dbt/techflow_warehouse/target/compiled/`.
- `dbt deps` installs `dbt_utils` and `audit_helper` into `dbt_packages/`.
- `dbt source freshness` checks `raw_db.crm.customer.updated_at` and `gold_db.transactions.fact_transactions.ingested_at`.
- `dbt build` creates `silver_db.customers.silver_customers`, `gold_db.customers.gold_customer_value`, and `gold_db.transactions.merchant_activity` (the Chapter 11 addition), then runs generic, singular, and unit tests. `macros/generate_schema_name.sql` is what makes those plain schema names resolve; without it dbt would append the custom schema to the profile's schema and build into `customers_customers`.
- `dbt parse` reports no deprecation warnings on dbt 1.10.
- `sqlmesh info` reports the Snowflake gateway and model count.
- `sqlmesh plan dev` proposes dev-environment changes before anything is promoted to prod.

## Troubleshooting

- **`source gold_transactions was not found`**: make sure `dbt/techflow_warehouse/models/gold/_sources.yml` is present. The article references this source from `gold_customer_value.sql`; the repo includes the source declaration so the model compiles.
- **`invalid identifier INGESTED_AT` on `raw_db.crm.customer`**: Chapter 5 creates `raw_db.crm.customer.updated_at`, not `ingested_at`. The repo uses `updated_at` for freshness on that source.
- **`Database RAW_DB does not exist`**: run Chapter 4 and Chapter 5 setup first.
- **`No module named dbt` or `sqlmesh`**: activate `.venv` and rerun `pip install -r requirements.txt`.
- **`dbt run-operation audit_helper_compare` cannot find `audit_helper`**: run `dbt deps` from `dbt/techflow_warehouse`.
- **`dbt build` creates objects in the wrong database**: confirm `dbt_project.yml` still routes `models/silver` to `silver_db` and `models/gold` to `gold_db`.
- **Objects land in `customers_customers` instead of `customers`**: `macros/generate_schema_name.sql` is missing or was renamed. dbt's built-in behavior concatenates the profile's schema with the model's custom schema.
- **`Failed to read package` naming a folder like `audit_helper 3`**: a previous `dbt deps` left duplicate package folders (common when the repository sits in a synced folder such as iCloud Drive or Google Drive). Delete the numbered duplicates under `dbt_packages/`, or remove `dbt_packages/` entirely and rerun `dbt deps`.
- **Nothing was built after running a `commands/` script**: both scripts stop before any mutating step. Rerun `dbt_commands.sh --apply`, or `sqlmesh_commands.sh --plan-dev` / `--plan-prod`.

## Additional Information

The files in `commands/` are captured command snippets, not an automated end-to-end installer. Run them section by section so you can review commands that create or promote warehouse objects before execution.
