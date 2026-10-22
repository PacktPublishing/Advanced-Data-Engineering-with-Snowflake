-- Chapter 18: OPTIONAL tag-based attribution (section "Defining the chargeback ledger").
-- Reference only. Object tagging requires Enterprise Edition or higher.
-- Prerequisites: the setup script; the report needs an approved reporting role
-- holding SNOWFLAKE.GOVERNANCE_VIEWER (TAG_REFERENCES) and SNOWFLAKE.USAGE_VIEWER
-- (WAREHOUSE_METERING_HISTORY)
-- and an approved warehouse, selected in Snowsight before running.
-- Validation: official Snowflake docs checked October 2026; SQL run live October 2026.
-- Placeholders: none. TAG_REFERENCES latency is up to 2 hours.
-- Roles: SYSADMIN owns CONTROL_DB.COST and the warehouses, so it creates and applies the tag.

-- BLOCK: cost-center tag on warehouses
USE ROLE SYSADMIN;
CREATE TAG CONTROL_DB.COST.COST_CENTER
  ALLOWED_VALUES 'CC_PAYMENTS', 'CC_RISK', 'CC_PLATFORM';
ALTER WAREHOUSE PAYMENTS_WH SET TAG CONTROL_DB.COST.COST_CENTER = 'CC_PAYMENTS';
ALTER WAREHOUSE RISK_WH SET TAG CONTROL_DB.COST.COST_CENTER = 'CC_RISK';
ALTER WAREHOUSE ADMIN_WH SET TAG CONTROL_DB.COST.COST_CENTER = 'CC_PLATFORM';

-- BLOCK: compute credits by current tag value
SELECT COALESCE(t.tag_value, 'UNTAGGED') AS cost_center,
       SUM(m.credits_used_compute) AS compute_credits
FROM snowflake.account_usage.warehouse_metering_history m
LEFT JOIN snowflake.account_usage.tag_references t
  ON m.warehouse_id = t.object_id
 AND t.domain = 'WAREHOUSE'
 AND t.tag_database = 'CONTROL_DB'
 AND t.tag_schema = 'COST'
 AND t.tag_name = 'COST_CENTER'
WHERE m.start_time >= DATEADD(day, -8, CURRENT_DATE())
  AND m.start_time < DATEADD(day, -1, CURRENT_DATE())
GROUP BY cost_center
ORDER BY compute_credits DESC;
-- EXPECT: one row per tag value plus UNTAGGED. The join uses the tag's CURRENT
-- value, so a warehouse re-tagged today moves all of last week's credits.
-- Observed October 2026 on the day the tags were applied: a single UNTAGGED row.
-- The window ends yesterday, before the lab warehouses existed, and TAG_REFERENCES
-- can take up to two hours to list a new tag. Rerun after the tagged warehouses
-- have run for a full day to see their cost centers.
