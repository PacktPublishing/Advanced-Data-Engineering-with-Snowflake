-- Chapter 16: Restoring a table from a backup set. Independent after chapter16_0_setup.sql.
-- Execute the named blocks in order and STOP ON ERROR.
-- Prerequisites: setup role, warehouse, database, and fixture tables.
-- Validation: live tested on Snowflake 10.33.101, 2026-09-21; see README.
-- Reader-specific substitutions use <REPLACE: description>.
-- Role: OPS_ENGINEER for lab work; explicit administrator blocks only where needed.

-- Run the BACKUP block first. COPY its returned backup_id into RESTORE.
-- This file is interactive: do not run through unresolved markers.
-- BACKUP: permanent table fixture; no retention lock or scheduled backups.
USE ROLE OPS_ENGINEER;
USE WAREHOUSE OPS_WH;
CREATE BACKUP SET OPS_DB.MONITORING.LEDGER_BACKUPS
  FOR TABLE OPS_DB.MONITORING.SETTLEMENT_LEDGER;
ALTER BACKUP SET OPS_DB.MONITORING.LEDGER_BACKUPS ADD BACKUP;
SHOW BACKUPS IN BACKUP SET OPS_DB.MONITORING.LEDGER_BACKUPS;

-- RESTORE: substitute the backup_id returned above before running.
CREATE TABLE OPS_DB.MONITORING.SETTLEMENT_RESTORED
  FROM BACKUP SET OPS_DB.MONITORING.LEDGER_BACKUPS
  IDENTIFIER '<REPLACE: backup_id>';
SELECT COUNT(*) AS rows_restored, SUM(amount) AS amount_restored
FROM OPS_DB.MONITORING.SETTLEMENT_RESTORED;

-- VERIFY FULL ROW CONTENT, including multiplicity, in both directions.
WITH expected AS (
  SELECT payment_id, batch_id, amount, COUNT(*) AS copies
  FROM OPS_DB.MONITORING.SETTLEMENT_LEDGER GROUP BY ALL
), restored AS (
  SELECT payment_id, batch_id, amount, COUNT(*) AS copies
  FROM OPS_DB.MONITORING.SETTLEMENT_RESTORED GROUP BY ALL
), missing_rows AS (SELECT * FROM expected MINUS SELECT * FROM restored),
  extra_rows AS (SELECT * FROM restored MINUS SELECT * FROM expected)
SELECT 'missing' AS discrepancy, * FROM missing_rows
UNION ALL SELECT 'extra', * FROM extra_rows;
-- Expected: zero rows. Counts and totals alone cannot prove row equality.
