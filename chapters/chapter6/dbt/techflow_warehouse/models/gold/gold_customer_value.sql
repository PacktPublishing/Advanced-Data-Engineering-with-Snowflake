{{ config(
    materialized='incremental',
    schema='customers',
    unique_key='customer_id',
    on_schema_change='fail'
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
    -- lifetime_revenue is a cumulative measure and the MERGE replaces the
    -- whole row on customer_id, so each affected customer's FULL history must
    -- be recomputed -- not just the new rows. Restrict to customers who have a
    -- new transaction since the last run; the LEFT JOIN above then
    -- re-aggregates all of their transactions, not only the recent ones.
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
