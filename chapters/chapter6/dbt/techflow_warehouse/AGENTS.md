# TechFlow Warehouse Project Rules

## Project Overview
A dbt project on Snowflake that materializes silver and gold layers from
raw_db landing tables. Silver is one-row-per-entity clean data.
Gold is Kimball-style facts and dimensions with plural names.

## Tech Stack
- dbt-core 1.10 or later with the dbt-snowflake adapter
- Snowflake databases: raw_db (raw), silver_db (integration), gold_db (analytics)
- Warehouse: BOOK_WH

## Coding Standards
- Use {{ ref('model_name') }} for internal references and {{ source('source', 'table') }} for raw inputs.
- Use lowercase snake_case for all column aliases.
- Default materialization is 'view' unless explicitly upgraded to 'materialized_view' or 'incremental'.
- For incremental models, always include an is_incremental() guard. Scope it on the
  event time column when the source has a trustworthy one; when timestamps are
  missing or unreliable, use the change-hash pattern in the dbt-incremental-model skill.
- For a cumulative measure (a lifetime or running total), the guard must select which
  keys changed and re-aggregate their full history. Filtering to new rows only makes
  the MERGE overwrite prior totals.
- Tests live in YAML for the generic four (unique, not_null, accepted_values, relationships) under the `data_tests:` key, not the legacy `tests:` key. Singular tests go in tests/ as standalone .sql files.

## Don'ts
- Never use SELECT *.
- Never reference a model without ref(); never reference a source without source().
- Never put business logic in the silver layer; clean and conform only.
