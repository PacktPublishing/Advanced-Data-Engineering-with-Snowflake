MODEL (
  name gold_db.customers.gold_customer_value,
  -- lifetime_revenue is a cumulative per-customer measure. An
  -- INCREMENTAL_BY_TIME_RANGE kind keyed on a MAX() aggregate would clobber
  -- prior totals on each cron run (it only sees the latest time slice), so
  -- this snapshot is recomputed in full each run.
  kind FULL,
  cron '@hourly',
  grain (
    customer_id
  ),
  audits (
    UNIQUE_VALUES(columns := (
      customer_id
    ))
  )
);

SELECT
  c.customer_id,
  c.customer_name,
  c.state,
  SUM(t.amount) AS lifetime_revenue,
  COUNT(t.transaction_id) AS lifetime_transactions,
  MAX(t.transaction_ts) AS last_transaction_ts
FROM silver_db.customers.silver_customers AS c
LEFT JOIN gold_db.transactions.fact_transactions AS t
  ON c.customer_id = t.customer_id
GROUP BY
  c.customer_id,
  c.customer_name,
  c.state