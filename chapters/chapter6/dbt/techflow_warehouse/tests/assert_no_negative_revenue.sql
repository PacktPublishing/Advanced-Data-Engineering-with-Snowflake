SELECT
    customer_id,
    lifetime_revenue
FROM {{ ref('gold_customer_value') }}
WHERE lifetime_revenue < 0
