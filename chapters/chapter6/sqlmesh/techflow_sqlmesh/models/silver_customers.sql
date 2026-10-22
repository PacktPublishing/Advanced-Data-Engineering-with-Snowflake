MODEL (
  name silver_db.customers.silver_customers,
  kind FULL,
  audits (
    UNIQUE_VALUES(columns := (
      customer_id
    )),
    NOT_NULL(columns := (customer_id, email))
  )
);

SELECT
  customer_id,
  customer_name,
  LOWER(TRIM(email)) AS email,
  SPLIT_PART(LOWER(TRIM(email)), '@', 2) AS email_domain,
  UPPER(TRIM(state)) AS state,
  postal_code,
  CURRENT_TIMESTAMP() AS sqlmesh_loaded_at
FROM raw_db.crm.customer
WHERE
  NOT customer_id IS NULL