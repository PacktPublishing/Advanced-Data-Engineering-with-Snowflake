---
name: dbt-incremental-model
description: Generate dbt incremental models on Snowflake using the change-hash pattern. Writes only rows whose tracked attributes changed.
---

# When to Use

Use when the user asks for a new incremental dbt model or an incremental refactor of an existing table model, and source timestamps are unreliable, missing, or untrusted. For append-only fact tables with a trustworthy event timestamp, use a time-column `is_incremental()` filter instead.

# What This Skill Provides

- `{{ config() }}` block for Snowflake MERGE with explicit `incremental_strategy` and `on_schema_change`
- A `chng_hash` column built from tracked attribute columns
- A `NOT EXISTS` clause that suppresses writes for unchanged rows
- A matching YAML file with `unique` + `not_null` on the surrogate key

# Instructions

1. Ask for: model name, source `ref()`/`source()`, the natural key column(s), and the attribute columns to track in the hash.
2. Place the SQL at the path matching the project layer (`models/int/...` or `models/anl/...`).
3. Configure `materialized='incremental'`, `unique_key='<entity>_key'` (the surrogate, not the natural key), `incremental_strategy='merge'`, `on_schema_change='append_new_columns'`.
4. Compute the surrogate key and the `chng_hash` with `dbt_utils.generate_surrogate_key()`.
5. Use `NOT EXISTS` (not `NOT IN`) to drop rows already present in `{{ this }}` with the same hash.
6. Generate the YAML test file alongside the SQL with `unique` + `not_null` on the surrogate key, and a `relationships` test for every FK to a parent dimension.

# Example

Every column is named explicitly, because the project's `AGENTS.md` forbids
`SELECT *`. Generated models must follow the same rule.

```sql
{{
    config(
        materialized = 'incremental',
        unique_key = 'account_key',
        incremental_strategy = 'merge',
        on_schema_change = 'append_new_columns'
    )
}}

with

source as (
    select
        account_id,
        account_name,
        account_type
    from {{ ref('int_sales__customer') }}
),

transformed as (
    select
        {{ dbt_utils.generate_surrogate_key(['account_id']) }} as account_key,
        account_id,
        account_name,
        account_type,
        {{ dbt_utils.generate_surrogate_key(['account_name', 'account_type']) }} as chng_hash,
        current_timestamp() as dbt_refresh_date
    from source
)

select
    account_key,
    account_id,
    account_name,
    account_type,
    chng_hash,
    dbt_refresh_date
from transformed
{% if is_incremental() %}
where not exists (
    select 1
    from {{ this }} as existing
    where existing.account_key = transformed.account_key
      and existing.chng_hash = transformed.chng_hash
)
{% endif %}
```
