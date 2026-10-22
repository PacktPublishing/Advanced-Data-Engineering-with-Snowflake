-- Chapter 18: cost allocation (section "Reconciling a shared compute allocation").
-- Run the setup script first. Independent of the role and isolation worksheets.
-- Prerequisites: sandbox account; setup completed.
-- Validation: official Snowflake docs checked October 2026; SQL run live October 2026.
-- Placeholders: none.
-- Roles: COST_READER reads the synthetic fixture; no account-history access needed.
-- Stop if any validation block returns rows.

-- BLOCK: source validation; expect zero rows; STOP if any check below returns rows.
USE ROLE COST_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE ADMIN_WH;
SELECT * FROM CONTROL_DB.COST.WAREHOUSE_HOURS
WHERE used_compute < 0 OR attributed_compute IS NULL
   OR attributed_compute < 0 OR attributed_compute > used_compute
   OR usage_start <> DATE_TRUNC('HOUR', usage_start);
SELECT account_key, warehouse_id, usage_start
FROM CONTROL_DB.COST.WAREHOUSE_HOURS
GROUP BY account_key, warehouse_id, usage_start
HAVING COUNT(*) <> 1;
-- Zero fixture rows is an error, not a zero-cost report.
SELECT COUNT(*) AS missing_fixture
FROM CONTROL_DB.COST.WAREHOUSE_HOURS
HAVING COUNT(*) = 0;

-- BLOCK: ownership shape; expect zero rows.
SELECT * FROM CONTROL_DB.COST.OWNERSHIP_MAP
WHERE valid_from >= valid_to OR allocation_share <= 0 OR allocation_share > 1
   OR cost_center = ''
   OR valid_from <> DATE_TRUNC('HOUR', valid_from)
   OR valid_to <> DATE_TRUNC('HOUR', valid_to);
-- Reject overlapping intervals for the SAME account, warehouse and cost center.
-- Separate cost centers may intentionally share the same effective interval.
WITH numbered AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY account_key, warehouse_id,
      cost_center, valid_from, valid_to, allocation_share) AS row_id
  FROM CONTROL_DB.COST.OWNERSHIP_MAP
)
SELECT a.account_key, a.warehouse_id, a.cost_center
FROM numbered a JOIN numbered b
  ON a.row_id < b.row_id
 AND a.account_key = b.account_key AND a.warehouse_id = b.warehouse_id
 AND a.cost_center = b.cost_center
 AND a.valid_from < b.valid_to AND a.valid_to > b.valid_from;

-- BLOCK: mapping validation; expect zero rows
USE ROLE COST_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE ADMIN_WH;
SELECT m.account_key, m.warehouse_id, m.usage_start
FROM CONTROL_DB.COST.WAREHOUSE_HOURS m
LEFT JOIN CONTROL_DB.COST.OWNERSHIP_MAP a
  ON m.account_key = a.account_key
 AND m.warehouse_id = a.warehouse_id
 AND m.usage_start >= a.valid_from
 AND m.usage_start < a.valid_to
GROUP BY m.account_key, m.warehouse_id, m.usage_start
HAVING COALESCE(SUM(a.allocation_share), 0) <> 1
    OR COUNT(a.cost_center) <> COUNT(DISTINCT a.cost_center)
    OR MIN(a.allocation_share) <= 0;

-- BLOCK: allocation; run only after ALL validations pass
USE ROLE COST_READER;
USE WAREHOUSE ADMIN_WH;
SELECT a.cost_center,
       SUM(m.used_compute * a.allocation_share) AS compute_credits,
       SUM((m.used_compute - m.attributed_compute)
           * a.allocation_share) AS idle_credits
FROM CONTROL_DB.COST.WAREHOUSE_HOURS m
JOIN CONTROL_DB.COST.OWNERSHIP_MAP a
  ON m.account_key = a.account_key
 AND m.warehouse_id = a.warehouse_id
 AND m.usage_start >= a.valid_from
 AND m.usage_start < a.valid_to
GROUP BY a.cost_center
ORDER BY a.cost_center;

-- BLOCK: reconciliation; expect COMPUTE_DIFFERENCE = 0 and IDLE_DIFFERENCE = 0.
WITH source AS (
  SELECT SUM(used_compute) AS used_compute,
         SUM(used_compute - attributed_compute) AS idle
  FROM CONTROL_DB.COST.WAREHOUSE_HOURS
), allocated AS (
  SELECT SUM(m.used_compute * a.allocation_share) AS used_compute,
         SUM((m.used_compute - m.attributed_compute) * a.allocation_share) AS idle
  FROM CONTROL_DB.COST.WAREHOUSE_HOURS m
  JOIN CONTROL_DB.COST.OWNERSHIP_MAP a
    ON m.account_key = a.account_key AND m.warehouse_id = a.warehouse_id
   AND m.usage_start >= a.valid_from AND m.usage_start < a.valid_to
)
SELECT s.used_compute - a.used_compute AS compute_difference,
       s.idle - a.idle AS idle_difference
FROM source s CROSS JOIN allocated a;
