-- ============================================================================
-- Chapter 6 (Transformation Frameworks) -- role setup
-- File: chapters/chapter6/sql/chapter6_setup_role.sql
--
-- Creates TRANSFORMER_ROLE, the least-privilege role the chapter's dbt and
-- SQLMesh exercises run under: read access on the two pipeline-owned source
-- tables, CREATE SCHEMA on silver_db and gold_db, and USAGE on BOOK_WH.
--
-- Relation to siblings: independent. Run once before the chapter's dbt or
-- SQLMesh steps; no other chapter6 file creates roles or grants.
--
-- Prerequisites:
--   * setup/snowflake_setup.sql (BOOK_WH) and the Chapter 4/5 setup scripts
--     (raw_db.crm.customer, gold_db.transactions.fact_transactions). The
--     guarded CREATE statements below keep this file runnable standalone.
--   * USERADMIN and SYSADMIN access. No ACCOUNTADMIN anywhere in this file.
--
-- Role convention (book standard): USERADMIN creates roles; SYSADMIN creates
-- objects and grants; ACCOUNTADMIN only where an account-level privilege
-- requires it, which is not the case here.
--
-- Placeholders: <REPLACE: ...> marks values you substitute. Objects the book
-- standardizes (BOOK_WH, raw_db, silver_db, gold_db) are used literally.
--
-- CI note: .github/workflows/chapter6-ci.yml reads the role from the SF_ROLE
-- secret; set that secret to TRANSFORMER_ROLE once this script has run.
-- ============================================================================

-- 1) Create the role.
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS TRANSFORMER_ROLE
  COMMENT = 'Chapter 6: least-privilege role for dbt and SQLMesh runs';

-- Roll the role up to SYSADMIN so administrators see what it builds.
GRANT ROLE TRANSFORMER_ROLE TO ROLE SYSADMIN;

-- Grant the role to the user who runs dbt, SQLMesh, and CoCo.
GRANT ROLE TRANSFORMER_ROLE TO USER "<REPLACE: your_username>";

-- 2) Objects and grants.
USE ROLE SYSADMIN;

-- Earlier chapters create these; IF NOT EXISTS keeps re-runs safe and makes
-- this file work on a fresh account.
CREATE WAREHOUSE IF NOT EXISTS BOOK_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
CREATE DATABASE IF NOT EXISTS raw_db;
CREATE DATABASE IF NOT EXISTS silver_db;
CREATE DATABASE IF NOT EXISTS gold_db;

GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE TRANSFORMER_ROLE;

-- Read the pipeline-owned sources the dbt project declares (raw_crm and
-- gold_transactions). FUTURE grants cover tables the pipelines re-create.
GRANT USAGE ON DATABASE raw_db TO ROLE TRANSFORMER_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE raw_db TO ROLE TRANSFORMER_ROLE;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE raw_db TO ROLE TRANSFORMER_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE raw_db TO ROLE TRANSFORMER_ROLE;
GRANT SELECT ON FUTURE TABLES IN DATABASE raw_db TO ROLE TRANSFORMER_ROLE;

-- Build targets. dbt and SQLMesh create their own schemas (customers,
-- customers__ci, silver_db__dev, and so on), so the role needs CREATE SCHEMA
-- on both databases; it then owns the schemas it creates.
GRANT USAGE, CREATE SCHEMA ON DATABASE silver_db TO ROLE TRANSFORMER_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE gold_db TO ROLE TRANSFORMER_ROLE;

-- gold_db also carries the pipeline-owned fact table the gold model reads.
GRANT USAGE ON ALL SCHEMAS IN DATABASE gold_db TO ROLE TRANSFORMER_ROLE;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE gold_db TO ROLE TRANSFORMER_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE gold_db TO ROLE TRANSFORMER_ROLE;
GRANT SELECT ON FUTURE TABLES IN DATABASE gold_db TO ROLE TRANSFORMER_ROLE;

-- 3) Make it your default role. CoCo in Snowsight always starts a session
-- under your DEFAULT role (Section 4 of the chapter), so this step is what
-- puts the agent on TRANSFORMER_ROLE. Omitting the username targets the
-- signed-in user; altering your own defaults needs no extra privilege.
ALTER USER SET DEFAULT_ROLE = TRANSFORMER_ROLE;

-- 4) Verification. The first statement lists the privileges granted to the
-- role; the second lists who holds it. Both should return rows.
SHOW GRANTS TO ROLE TRANSFORMER_ROLE;
SHOW GRANTS OF ROLE TRANSFORMER_ROLE;
