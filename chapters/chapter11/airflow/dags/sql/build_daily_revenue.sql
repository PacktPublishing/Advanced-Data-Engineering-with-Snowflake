-- Chapter 11 preserves this full-table statement from the manuscript.
-- WARNING: INSERT OVERWRITE replaces the entire target table, not one date
-- partition. Static validation reads this file but intentionally never runs it.
INSERT OVERWRITE INTO gold_db.transactions.merchant_daily_revenue
SELECT
    merchant_id,
    DATE_TRUNC('day', transaction_ts) AS revenue_date,
    COUNT(*) AS transaction_count,
    SUM(amount) AS gross_revenue
FROM silver_db.transactions.transactions_clean
WHERE status = 'COMPLETED'
GROUP BY 1, 2;
