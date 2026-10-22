-- Added by Chapter 11 (external orchestration). Reads the cleansed transactions
-- through the declared `transactions` source, which is what lets Dagster connect
-- the dbt graph to the hand-written transactions_clean asset. Tagged `nightly`
-- so each orchestrator's `tag:nightly` selector schedules it.
--
-- Grain is one row per merchant. transactions_clean carries no customer_id
-- (see chapter9_setup.sql), so this mart cannot join the customer marts.
{{ config(
    materialized='view',
    database='gold_db',
    schema='transactions',
    tags=['nightly']
) }}

SELECT
    merchant_id,
    COUNT(*) AS transaction_count,
    COUNT(DISTINCT DATE_TRUNC('day', transaction_ts)) AS active_days,
    SUM(amount) AS gross_amount,
    MAX(transaction_ts) AS last_transaction_ts,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM {{ source('transactions', 'transactions_clean') }}
WHERE status = 'COMPLETED'
GROUP BY merchant_id
