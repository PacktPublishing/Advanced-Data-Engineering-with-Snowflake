---
name: dbt-multi-source-merge
description: Generate dbt incremental models on Snowflake that MERGE one keyed grain from two or more upstream relations. Combines a dimension with an aggregated fact without overwriting unchanged keys.
---

# When to Use

Use when a single output row is assembled from more than one upstream relation and the result must be merged incrementally on a shared key, for example joining the cleaned `silver_customers` dimension to the `gold_db.transactions.fact_transactions` fact to produce `gold_customer_value`. Prefer this over the change-hash incremental skill when the driver of change is *new rows in a second source* (transactions) rather than *attribute drift in one source*.

# What This Skill Provides

- A `{{ config() }}` block with `incremental_strategy='merge'`, `unique_key` on the shared grain, and `on_schema_change='append_new_columns'`
- A join across two declared upstreams: a `ref()` to the silver dimension and a `source()` to the gold fact
- A changed-key `is_incremental()` filter that re-aggregates each affected key's FULL history, so a cumulative measure is never clobbered by a partial time slice
- A matching YAML file with `unique` + `not_null` on the merge key

# Instructions

1. Ask for: model name, the shared grain column(s), the dimension `ref()`, the fact `source()`/`ref()`, and the measures to aggregate.
2. Place the SQL under the layer that owns the output grain (`models/gold/...` for a customer-grain rollup like this one).
3. Configure `materialized='incremental'`, `schema='customers'`, `unique_key='<grain>'`, `incremental_strategy='merge'`, `on_schema_change='append_new_columns'`.
4. Reference every upstream explicitly: `{{ ref('silver_customers') }}` for owned models, `{{ source('gold_transactions', 'fact_transactions') }}` for inputs the project does not own. Never reference a relation without `ref()`/`source()`, and never `SELECT *`.
5. For a cumulative measure, scope the `is_incremental()` rebuild to *which keys changed* (keys with a transaction newer than `MAX(last_transaction_ts)` in `{{ this }}`), then let the unfiltered join re-aggregate each of those keys' full history. Do not filter to only the new rows.
6. Generate the YAML test file alongside the SQL with `unique` + `not_null` on the merge key, and a `relationships` test from the fact key back to the dimension.

# Example

```sql
{{ config(
    materialized='incremental',
    schema='customers',
    unique_key='customer_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

SELECT
    c.customer_id,
    c.customer_name,
    c.state,
    SUM(t.amount) AS lifetime_revenue,
    COUNT(t.transaction_id) AS lifetime_transactions,
    MAX(t.transaction_ts) AS last_transaction_ts,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM {{ ref('silver_customers') }} AS c
LEFT JOIN {{ source('gold_transactions', 'fact_transactions') }} AS t
    ON c.customer_id = t.customer_id
{% if is_incremental() %}
    -- Re-aggregate every customer who has a new transaction since the last
    -- run. The MERGE replaces the whole row on customer_id, so each changed
    -- customer's FULL history is recomputed, not just the new rows.
    WHERE c.customer_id IN (
        SELECT new_tx.customer_id
        FROM {{ source('gold_transactions', 'fact_transactions') }} AS new_tx
        WHERE new_tx.transaction_ts > (
            SELECT MAX(existing.last_transaction_ts)
            FROM {{ this }} AS existing
        )
    )
{% endif %}
GROUP BY c.customer_id, c.customer_name, c.state
```
