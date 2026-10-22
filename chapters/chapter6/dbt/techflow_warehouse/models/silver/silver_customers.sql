{{ config(
    materialized='view',
    schema='customers'
) }}

SELECT
    customer_id,
    customer_name,
    LOWER(TRIM(email)) AS email,
    UPPER(TRIM(state)) AS state,
    postal_code,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM {{ source('raw_crm', 'customer') }}
WHERE customer_id IS NOT NULL
