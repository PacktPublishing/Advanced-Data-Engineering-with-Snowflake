-- Chapter 18: OPTIONAL noisy-neighbor check (section "Detecting noisy neighbors and planning tenant growth").
-- Independent read-only SELECTs against account history; not part of the core lab.
-- Prerequisites: an approved reporting role holding SNOWFLAKE.GOVERNANCE_VIEWER
-- (QUERY_HISTORY access) and an approved reporting warehouse. Select both in
-- Snowsight before running. The core lab roles do not hold this database role.
-- Validation: official Snowflake docs checked October 2026. The weekly block ran
-- live in October 2026 without the blocked_s column, which was added October 14
-- with the hourly block; both are PENDING a live run.
-- Placeholders: none in the SQL; the role and warehouse are chosen in Snowsight.
-- QUERY_HISTORY latency is up to 45 minutes. Times are in milliseconds.

-- BLOCK: execution share, overload queueing and lock waits by warehouse and role
SELECT warehouse_name, role_name,
       COUNT(*) AS queries,
       ROUND(SUM(execution_time) / 1000) AS execution_s,
       ROUND(SUM(queued_overload_time) / 1000) AS queued_s,
       ROUND(SUM(transaction_blocked_time) / 1000) AS blocked_s,
       ROUND(RATIO_TO_REPORT(SUM(execution_time))
             OVER (PARTITION BY warehouse_name), 2) AS execution_share
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD(day, -8, CURRENT_DATE())
  AND start_time < DATEADD(day, -1, CURRENT_DATE())
  AND warehouse_name IS NOT NULL
GROUP BY warehouse_name, role_name
ORDER BY warehouse_name, execution_share DESC;
-- EXPECT: one row per warehouse and role, possibly none in a new account.
-- Weekly totals name CANDIDATES only. A role with a high execution_share on a
-- warehouse where other roles carry queued_s is worth checking hour by hour.
-- blocked_s is time waiting on locks, which more compute does not fix.

-- BLOCK: hourly overlap on one warehouse (set the name before running)
SET contended_wh = 'PAYMENTS_WH';
SELECT DATE_TRUNC('hour', start_time) AS usage_hour, role_name,
       ROUND(SUM(execution_time) / 1000) AS execution_s,
       ROUND(SUM(queued_overload_time) / 1000) AS queued_s
FROM snowflake.account_usage.query_history
WHERE warehouse_name = $contended_wh
  AND start_time >= DATEADD(day, -8, CURRENT_DATE())
  AND start_time < DATEADD(day, -1, CURRENT_DATE())
GROUP BY usage_hour, role_name
HAVING SUM(execution_time) > 0 OR SUM(queued_overload_time) > 0
ORDER BY usage_hour, execution_s DESC;
-- EXPECT: one row per hour and role. The move is justified only when the busy
-- role's execution and the other roles' queued seconds land in the SAME hours.
