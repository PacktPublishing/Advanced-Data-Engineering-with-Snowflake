-- =========================================================================
-- Chapter 11, Section 5.3: Query tagging and cost attribution
-- =========================================================================
-- REVIEW ONLY. The ALTER statement is not a manuscript block; the manuscript
-- argues against it (block 24 sets the tag through hook_params instead). Run it on
-- the same session as the statement being attributed; a different task or
-- connection will not inherit the tag. Live DAGs set the tag through
-- hook_params so it includes the DAG, task, and partition.
-- =========================================================================

ALTER SESSION SET QUERY_TAG = 'airflow:techflow_transform:build_daily_revenue';

-- Per-query compute attribution belongs in QUERY_ATTRIBUTION_HISTORY, not
-- QUERY_HISTORY. This read-only query excludes warehouse idle time, storage,
-- data transfer, cloud-services charges, serverless services, and very short
-- queries. Account Usage latency can be up to eight hours.
SELECT
    query_tag,
    SUM(credits_attributed_compute) AS warehouse_compute_credits,
    SUM(
        COALESCE(credits_used_query_acceleration, 0)
    ) AS query_acceleration_credits
FROM snowflake.account_usage.query_attribution_history
WHERE start_time >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())
  AND start_time < CURRENT_TIMESTAMP()
  AND query_tag LIKE 'airflow:techflow_transform:%'
GROUP BY query_tag
ORDER BY warehouse_compute_credits DESC;
