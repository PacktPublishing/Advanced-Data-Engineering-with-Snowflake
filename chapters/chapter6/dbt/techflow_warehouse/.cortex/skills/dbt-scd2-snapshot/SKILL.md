---
name: dbt-scd2-snapshot
description: Generate dbt SCD Type 2 snapshots on Snowflake using the close-and-insert MERGE pattern. Preserves prior row versions of a dimension instead of overwriting them.
---

# When to Use

Use when the user needs to track how a dimension changes over time (Type 2 history) rather than keep only the current state. The canonical case here is `dim_customers`: a customer's `state` or `email` changes and the business needs both the old and the new version with valid-from/valid-to ranges. Reach for a snapshot over a `dynamic_table` or `incremental` model whenever prior row versions must survive, since dynamic tables refresh to the current state and cannot express SCD2 history.

# What This Skill Provides

- A `{% snapshot %}` block in the `snapshots/` folder (not `models/`), which dbt implements as the close-and-insert MERGE you would otherwise hand-write
- A `check` strategy on the tracked attribute columns, used because the silver layer's `dbt_loaded_at` is a `CURRENT_TIMESTAMP()` and is not a trustworthy change timestamp
- `unique_key='customer_id'` so dbt keys the MERGE on the natural key and manages `dbt_valid_from` / `dbt_valid_to` automatically
- A matching YAML file with `unique` + `not_null` on the snapshot surrogate key (`dbt_scd_id`)

# Instructions

1. Ask for: snapshot name, source `ref()`/`source()`, the natural key column, and the attribute columns whose changes should open a new version.
2. Place the file under `snapshots/<name>.sql`, not `models/`. dbt only honors `{% snapshot %}` blocks inside the snapshots path.
3. Prefer `strategy='check'` with an explicit `check_cols` list when the source has no reliable update timestamp (the silver models here do not). Use `strategy='timestamp'` with `updated_at` only when reading directly from `raw_db.crm.customer`, which carries a real `updated_at`.
4. Set `unique_key='customer_id'`, `target_schema='customers'`, and let dbt own `dbt_valid_from`, `dbt_valid_to`, `dbt_scd_id`, and `dbt_updated_at`.
5. Never widen the snapshot into business logic. Snapshot the conformed silver row; downstream gold dimensions read from the snapshot with `ref()`.
6. Generate the YAML test file alongside the snapshot with `unique` + `not_null` on `dbt_scd_id`, and `not_null` on `customer_id` and `dbt_valid_from`.

# Example

```sql
{% snapshot dim_customers %}
{{
    config(
        target_schema='customers',
        unique_key='customer_id',
        strategy='check',
        check_cols=['customer_name', 'email', 'state', 'postal_code'],
        invalidate_hard_deletes=true
    )
}}

SELECT
    customer_id,
    customer_name,
    email,
    state,
    postal_code
FROM {{ ref('silver_customers') }}
WHERE customer_id IS NOT NULL
{% endsnapshot %}
```
