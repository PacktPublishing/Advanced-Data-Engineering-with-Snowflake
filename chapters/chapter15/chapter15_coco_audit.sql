-- Chapter 15: Checked evidence for the optional CoCo audit prompt (Packt, 2026)
-- Read-only. Requires setup and the earlier quality/access exercises.
-- Run before teardown; prior dropped lab objects can remain in history.
-- Account Usage metadata can lag. A missing lifecycle row is not proof that
-- a measurement belongs to the current table with the same name.
-- Placeholder convention: book and BOOK_WH are defaults; no SQL placeholders.
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- Retain IDs and lifecycle evidence; timestamps are normalized to UTC.
SELECT CONVERT_TIMEZONE('UTC', d.scheduled_time)::TIMESTAMP_NTZ AS scheduled_utc,
       CONVERT_TIMEZONE('UTC', d.measurement_time)::TIMESTAMP_NTZ AS measured_utc,
       d.table_id, d.metric_id, d.expectation_name,
       d.value, d.expectation_violated,
       CONVERT_TIMEZONE('UTC', t.created)::TIMESTAMP_NTZ AS table_created_utc,
       CONVERT_TIMEZONE('UTC', t.deleted)::TIMESTAMP_NTZ AS table_deleted_utc
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS d
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TABLES t ON d.table_id = t.table_id
WHERE d.table_database = 'GOVERNANCE_DB'
  AND d.table_schema = 'TRANSACTIONS' AND d.table_name = 'FACT_TRANSACTIONS'
  AND d.metric_database = 'GOVERNANCE_DB'
  AND d.metric_schema = 'QUALITY' AND d.metric_name = 'ORPHAN_MERCHANT_COUNT'
  AND d.expectation_name = 'NO_ORPHAN_MERCHANTS'
  AND d.measurement_time >= DATEADD('DAY', -1, CURRENT_TIMESTAMP())
ORDER BY d.measurement_time DESC LIMIT 20;
-- Expected after the quality exercise: value 1 / TRUE followed by 0 / FALSE.
-- If TABLE_DELETED_UTC is present, that table incarnation was dropped.
-- NULL lifecycle metadata may reflect view latency; preserve the uncertainty.

SELECT ah.query_id,
       CONVERT_TIMEZONE('UTC', ah.query_start_time)::TIMESTAMP_NTZ AS accessed_utc,
       ah.user_name, qh.role_name, qh.secondary_role_stats,
       obj.value:objectId::NUMBER AS table_id,
       obj.value:columns AS accessed_columns, ah.policies_referenced
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh ON ah.query_id = qh.query_id,
LATERAL FLATTEN(input => ah.base_objects_accessed) obj
WHERE ah.query_start_time >= DATEADD('DAY', -1, CURRENT_TIMESTAMP())
  AND obj.value:objectName::STRING = 'GOVERNANCE_DB.CUSTOMERS.DIM_CUSTOMERS'
ORDER BY ah.query_start_time DESC LIMIT 10;
-- Expected: recorded primary roles, secondary-role statistics when present,
-- accessed columns, and policy references. JSON null is not a missing column.
-- Treat null statistics as unknown; they alone do not prove secondary roles
-- were disabled. Non-null statistics describe roles evaluated by the query.
-- These records do not establish the values returned or complete historical
-- role membership. Keep query IDs for review; do not sample customer rows.
-- Latency references, checked 2026-09-08:
-- ACCESS_HISTORY: up to 180 minutes (3 hours).
-- https://docs.snowflake.com/en/sql-reference/account-usage/access_history
-- QUERY_HISTORY: up to 45 minutes.
-- https://docs.snowflake.com/en/sql-reference/account-usage/query_history
