-- Chapter 8, Section 3.2, step 3: verify the output the batch job wrote.
-- A status of SUCCEEDED confirms the process exited cleanly, not that the data
-- is right. Seven rows of plausible daily totals confirm the migrated job
-- wrote what the Spark original wrote. The parity harness in Section 6.4
-- automates this comparison against the Spark baseline.

SELECT settle_date,
       COUNT(*)                AS merchants,
       SUM(settled_amount_usd) AS total_settled_usd
FROM gold_db.transactions.daily_settlement
GROUP BY settle_date
ORDER BY settle_date DESC
LIMIT 7;
