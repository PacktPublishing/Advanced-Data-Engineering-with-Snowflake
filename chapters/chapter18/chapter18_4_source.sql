-- Chapter 18: OPTIONAL warehouse-hour source projection (section "Reconciling a shared compute allocation").
-- Independent SELECT; not needed for synthetic exercises. No setup changes here.
-- Prerequisites: an approved reporting role with SNOWFLAKE.USAGE_VIEWER,
-- and an approved reporting warehouse. Core COST_READER lacks that broad role.
-- Validation: official docs checked October 2026; SQL run live October 2026.
-- Placeholders: none in the SQL; the role and warehouse are chosen in Snowsight.
-- Role: delegated reporting identity, not a team workload identity.
-- Select your approved role and warehouse in Snowsight before running.
-- Account key uses organization and account locator; retain region metadata in registry.
-- Seven complete UTC days, omitting yesterday/today for telemetry settlement.
-- Preserve NULL attribution (Adaptive/unavailable). Do not convert NULL to zero.
ALTER SESSION SET TIMEZONE = 'UTC';
SELECT CURRENT_ORGANIZATION_NAME() || '.' || CURRENT_REGION()
         || '.' || CURRENT_ACCOUNT() AS account_key,
       warehouse_id,
       start_time::TIMESTAMP_NTZ AS usage_start,
       credits_used_compute AS used_compute,
       credits_attributed_compute_queries AS attributed_compute
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD(day, -8, CURRENT_DATE())
  AND start_time < DATEADD(day, -1, CURRENT_DATE())
  AND credits_used_compute > 0
ORDER BY warehouse_id, usage_start;
-- Hours with no compute carry nothing to allocate and would fail the owner check.
-- The October 2026 live run returned zero-credit rows for warehouse_id 0, which this
-- filter removes.
-- EXPECT: historical hourly records, possibly none. Never write them over the fixture.
-- This projects all visible warehouses, including unsupported NULL-attribution rows.
-- Route NULL rows to a separate compute-model pipeline before allocating idle cost.
