-- Chapter 11, Section 5.2: incremental alternative to the full-table rebuild.
-- Replaces only the run's day inside one transaction, so a rerun of a given
-- {{ ds }} rebuilds that day and leaves every other day untouched. Use this
-- instead of build_daily_revenue.sql once the table grows past cheap-rebuild
-- size. The explicit BEGIN/COMMIT is what makes the DELETE+INSERT atomic: both
-- statements must run on one connection in one task, never split across tasks.
-- Static validation reads this file but never runs it.
BEGIN;

DELETE FROM gold_db.transactions.merchant_daily_revenue
WHERE revenue_date = TO_DATE('{{ ds }}');

INSERT INTO gold_db.transactions.merchant_daily_revenue
SELECT
    merchant_id,
    DATE_TRUNC('day', transaction_ts) AS revenue_date,
    COUNT(*) AS transaction_count,
    SUM(amount) AS gross_revenue
FROM silver_db.transactions.transactions_clean
WHERE status = 'COMPLETED'
  AND DATE_TRUNC('day', transaction_ts) = TO_DATE('{{ ds }}')
GROUP BY 1, 2;

COMMIT;
