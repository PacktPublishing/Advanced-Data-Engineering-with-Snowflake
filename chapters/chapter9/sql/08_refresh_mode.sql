-- =========================================================================
-- Chapter 9, Section 3.2: Choosing a refresh mode
-- =========================================================================
-- Inspects the refresh mode Snowflake resolved for a Dynamic Table with
-- SHOW DYNAMIC TABLES. When refresh_mode is INCREMENTAL the reason is NULL;
-- when it is FULL, refresh_mode_reason names the construct that blocked
-- incremental refresh.
--
-- Prerequisite: 07_dynamic_table.sql creates the silver table with AUTO.
-- Inspect it here before 09_dt_chain_downstream.sql creates the gold table.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- 3.2  Inspect the resolved refresh mode
SHOW DYNAMIC TABLES LIKE 'transactions_clean_dt' IN SCHEMA silver_db.transactions
    ->> SELECT "name", "refresh_mode", "refresh_mode_reason" FROM $1;
