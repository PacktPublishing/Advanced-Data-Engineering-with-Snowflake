---
name: dbt-silver-cleaning
description: Generate dbt silver-layer cleaning models on Snowflake that conform a single raw landing table into one clean row per entity. Cleans and conforms only, no business logic.
---

# When to Use

Use when promoting a `raw_db` landing table into the silver layer, for example turning `raw_db.crm.customer` into `silver_customers`. The silver layer is one-row-per-entity clean data: trim, lowercase, uppercase, normalize, and drop unusable rows. Push joins, aggregations, and any business measures up to the gold layer instead.

# What This Skill Provides

- A `{{ config() }}` block defaulting to `materialized='view'` (always-fresh, nothing to maintain) with `schema='customers'`
- A `{{ source(...) }}` read from the raw landing table so lineage and freshness checks register the input
- Standard conforming expressions: `LOWER(TRIM(...))` on email, `UPPER(TRIM(...))` on state codes, optional derived columns like an email domain via `SPLIT_PART`
- A `WHERE <natural_key> IS NOT NULL` guard and a matching YAML file with `unique` + `not_null` + `accepted_values`

# Instructions

1. Ask for: model name, the raw `source()` table, the natural key column, and which text columns need normalizing.
2. Place the SQL at `models/silver/<name>.sql`. dbt derives the schema namespace from the folder, and the silver cleaning models land in the `customers` schema.
3. Configure `materialized='view'` and `schema='customers'`. Only promote to `table`, `dynamic_table`, or `incremental` when read latency or cost demands it; the default is view-first.
4. Read the raw table with `{{ source('raw_crm', 'customer') }}` (registered in `models/silver/_sources.yml`), never a bare table reference, and never `SELECT *`.
5. Clean and conform only: `LOWER(TRIM(email))`, `UPPER(TRIM(state))`, lowercase snake_case aliases, a `CURRENT_TIMESTAMP() AS dbt_loaded_at` audit column, and `WHERE customer_id IS NOT NULL`. Do not join other tables or compute business measures here.
6. Generate the YAML test file alongside the SQL with `unique` + `not_null` on the natural key, `not_null` on `email`, and `accepted_values` on `state` with the US state and Canadian province/territory codes.

# Example

```sql
{{ config(
    materialized='view',
    schema='customers'
) }}

SELECT
    customer_id,
    customer_name,
    LOWER(TRIM(email)) AS email,
    SPLIT_PART(LOWER(TRIM(email)), '@', 2) AS email_domain,
    UPPER(TRIM(state)) AS state,
    postal_code,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM {{ source('raw_crm', 'customer') }}
WHERE customer_id IS NOT NULL
```
