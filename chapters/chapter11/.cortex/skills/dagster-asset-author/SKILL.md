---
name: dagster-asset-author
description: Generate current Dagster Components projects, Snowflake assets, dbt lineage, and schedules using Chapter 11 production patterns.
---

# dagster-asset-author

Use this skill to author or review Dagster code for Snowflake pipelines. It
encodes the Chapter 11 asset graph and the current `dg` Components layout so
generated projects do not fall back to legacy repository definitions or
Python-only dbt integrations.

## Required workflow

1. Inspect the target project's `pyproject.toml` before generating files.
2. Confirm `[tool.dg]` sets `directory_type = "project"` and
   `[tool.dg.project]` identifies `root_module`, `defs_module`, and
   `code_location_target_module`.
3. Prefer an available integration Component. For dbt Core, scaffold:

   ```bash
   dg scaffold defs dagster_dbt.DbtProjectComponent <name> \
     --project-path <path-to-dbt-project>
   ```

4. Keep the generated component under the configured `defs_module`. Resolve
   its project path from `{{ context.project_root }}` and use dbt selection
   syntax such as `tag:nightly`.
5. Keep custom Snowflake SQL in focused Python assets. Inject
   `SnowflakeResource`; never construct a connector or credentials inside an
   asset.
6. Load component definitions with `dg.load_from_defs_folder()` and combine
   them with handwritten assets, resources, and schedules using
   `dg.Definitions.merge()`.
7. Register schedules in `Definitions`, set `execution_timezone="UTC"`
   explicitly, and target an asset selection rather than hand-ordering steps.

## Snowflake rules

- Use key-pair authentication only.
- Read `account`, `user`, and `private_key_path` through `dagster.EnvVar`. This
  chapter uses an unencrypted key file, so no passphrase field appears; an
  encrypted key adds `private_key_password=dg.EnvVar("SNOWFLAKE_PRIVATE_KEY_PASSWORD")`.
- Open both objects with context managers:

  ```python
  with snowflake.get_connection() as connection:
      with connection.cursor() as cursor:
          cursor.execute(sql)
  ```

- Declare ordering with asset dependencies. Use `deps=[upstream_asset]` when
  the upstream asset returns no in-memory value.
- Keep compute in Snowflake. Do not pull warehouse data into the Dagster
  process for transformation.
- Show every data-modifying SQL statement for human review before execution.
  Never run, materialize, or schedule generated writes automatically.

## dbt lineage rules

- Use `DbtProjectComponent`; do not generate `@dbt_assets` for a new project.
- Select the intended workload in `defs.yaml`, for example
  `select: "tag:nightly"`.
- Every dbt model must use `ref()` or `source()` for relations it reads.
- To connect a handwritten Dagster asset to a dbt source, make the keys
  identical:

  ```yaml
  sources:
    - name: transactions
      tables:
        - name: transactions_clean
          config:
            meta:
              dagster:
                asset_key: ["transactions_clean"]
  ```

  ```sql
  FROM {{ source('transactions', 'transactions_clean') }}
  ```

- Do not create a dbt model whose asset key duplicates a handwritten asset.

## Review and validation

After human review and dependency installation, run only definition checks:

```bash
dg check toml
dg check yaml
dg check defs
dg list defs
```

These commands may parse a dbt manifest but must not materialize assets or
execute model SQL. Do not run `dg launch`, `dbt build`, `dbt run`, a Docker
stack, or any SQL as part of static validation.

Confirm the final project has:

1. Valid `tool.dg` project metadata.
2. Component definitions loaded and merged with Python definitions.
3. Encrypted key passphrase supplied through `EnvVar`.
4. Explicit connection and cursor context managers.
5. A registered schedule with an explicit UTC timezone.
6. Matching handwritten/dbt source asset keys and visible lineage.
7. No committed secrets, private keys, `.env`, dbt `target/`, or build output.
