-- Chapter 11, Section 1.5: partition-scoped rebuild for the split DAGs.
--
-- Same statement as build_daily_revenue_incremental.sql, but keyed on the
-- run's partition instead of its data interval: a partitioned DAG has no data
-- interval, so the ds template variable is not defined here. The
-- partition_date | ds filter formats the resolved partition as YYYY-MM-DD and
-- requires Airflow 3.3+.
--
-- The explicit BEGIN opens a transaction that spans both statements on this
-- session, so the DELETE and INSERT commit together and a retry cannot leave
-- the day half-written. Keep the block to DML: a DDL statement inside it would
-- commit the open transaction implicitly. The operator sends this file with
-- split_statements=False so it arrives as one multi-statement request.
--
-- REVIEW ONLY for static validation: this file is read, never executed, by
-- commands/validate.sh.
BEGIN;

DELETE FROM gold_db.transactions.merchant_daily_revenue
WHERE revenue_date = TO_DATE('{{ partition_date | ds }}');

INSERT INTO gold_db.transactions.merchant_daily_revenue
SELECT
    merchant_id,
    DATE_TRUNC('day', transaction_ts) AS revenue_date,
    COUNT(*) AS transaction_count,
    SUM(amount) AS gross_revenue
FROM silver_db.transactions.transactions_clean
WHERE status = 'COMPLETED'
  AND DATE_TRUNC('day', transaction_ts) = TO_DATE('{{ partition_date | ds }}')
GROUP BY 1, 2;

COMMIT;
