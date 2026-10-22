-- Chapter 18: denied access and team delegation (section "Testing denied access and delegation").
-- Run after the delegated-workspace worksheet. DO NOT run as a batch.
-- Prerequisites: sandbox account; setup and the workspace worksheet completed.
-- Validation: official Snowflake docs checked October 2026; blocks 1 and 2 run live
-- October 2026, and block 5's GRANT, SELECT and REVOKE ran live in October 2026 as
-- the original delegation block. Blocks 3 and 4 (account-privilege denial,
-- publication), block 5's SHOW GRANTS line and the audit block were added
-- October 14, 2026 and are PENDING a live run; their EXPECT lines are from the docs.
-- Placeholders: none.
-- Roles: RISK_READER, PAYMENTS_BUILDER and PAYMENTS_ADMIN are each expected to be
-- denied once, at their own layer; PAYMENTS_ADMIN, as schema owner, is expected
-- to succeed when it publishes, and, as database-role owner, to succeed when it
-- grants the WORKING schema to Risk (block 5 shows what the design cannot stop).
-- Run each statement individually and confirm its positive control first.

-- BLOCK: Risk positive control and Payments denial
USE ROLE RISK_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE RISK_WH;
SELECT COUNT(*) AS reviews FROM RISK_DB.WORK.REVIEW_QUEUE;
SELECT COUNT(*) FROM PAYMENTS_DB.WORK.DAILY_BATCH;
-- EXPECT (observed October 2026): 2 reviews, then SQL compilation error:
-- Database 'PAYMENTS_DB' does not exist or not authorized. Your primary role
-- RISK_READER must have USAGE or any other privilege granted on DATABASE PAYMENTS_DB.

-- BLOCK: builder delegation attempt; EXPECT DENIAL
USE ROLE PAYMENTS_BUILDER;
USE SECONDARY ROLES NONE;
GRANT SELECT ON TABLE PAYMENTS_DB.WORK.DAILY_BATCH
  TO ROLE RISK_READER;
-- EXPECT (observed October 2026): SQL execution error: Not authorized in a
-- managed access schema. Use the schema owner role or a role with the
-- MANAGE GRANTS privilege.

-- BLOCK: team-admin account privilege attempt; EXPECT DENIAL
USE ROLE PAYMENTS_ADMIN;
USE SECONDARY ROLES NONE;
CREATE WAREHOUSE PAYMENTS_SCRATCH_WH WAREHOUSE_SIZE = XSMALL;
-- EXPECT (pending live run): SQL access control error: Insufficient privileges
-- to operate on account '<account>'. CREATE WAREHOUSE is an account privilege
-- the team administrator never received. If it succeeds, drop the warehouse as
-- SYSADMIN and inspect the administrator's grants.

-- BLOCK: team-admin publication and revocation; EXPECT SUCCESS, final query fails
USE ROLE PAYMENTS_ADMIN;
USE SECONDARY ROLES NONE;
CREATE VIEW PAYMENTS_DB.PUBLISHED.DAILY_SETTLEMENT AS
  SELECT batch_id, settled_usd FROM PAYMENTS_DB.WORK.DAILY_BATCH;
CREATE DATABASE ROLE PAYMENTS_DB.PUBLISHED_READER;
GRANT USAGE ON DATABASE PAYMENTS_DB
  TO DATABASE ROLE PAYMENTS_DB.PUBLISHED_READER;
GRANT USAGE ON SCHEMA PAYMENTS_DB.PUBLISHED
  TO DATABASE ROLE PAYMENTS_DB.PUBLISHED_READER;
GRANT SELECT ON VIEW PAYMENTS_DB.PUBLISHED.DAILY_SETTLEMENT
  TO DATABASE ROLE PAYMENTS_DB.PUBLISHED_READER;
GRANT DATABASE ROLE PAYMENTS_DB.PUBLISHED_READER TO ROLE RISK_READER;
USE ROLE RISK_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE RISK_WH;
SELECT COUNT(*) AS batches FROM PAYMENTS_DB.PUBLISHED.DAILY_SETTLEMENT;
SELECT COUNT(*) FROM PAYMENTS_DB.WORK.DAILY_BATCH;
USE ROLE PAYMENTS_ADMIN;
REVOKE DATABASE ROLE PAYMENTS_DB.PUBLISHED_READER FROM ROLE RISK_READER;
USE ROLE RISK_READER;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) FROM PAYMENTS_DB.PUBLISHED.DAILY_SETTLEMENT;
-- EXPECT (pending live run): the view and database role are created, Risk's
-- view query returns BATCHES 2, and Risk's WORK query fails with
-- Schema 'PAYMENTS_DB.WORK' does not exist or not authorized, because the role
-- carries USAGE on the database but not on WORK. After the REVOKE, the final
-- view query fails with the database error from block 1.

-- BLOCK: what the design cannot stop; EXPECT SUCCESS, then revoke
USE ROLE PAYMENTS_ADMIN;
USE SECONDARY ROLES NONE;
GRANT DATABASE ROLE PAYMENTS_DB.WORK_READER TO ROLE RISK_READER;
USE ROLE RISK_READER;
USE SECONDARY ROLES NONE;
SHOW GRANTS TO ROLE RISK_READER;
USE WAREHOUSE RISK_WH;
SELECT COUNT(*) AS batches FROM PAYMENTS_DB.WORK.DAILY_BATCH;
USE ROLE PAYMENTS_ADMIN;
REVOKE DATABASE ROLE PAYMENTS_DB.WORK_READER FROM ROLE RISK_READER;
-- EXPECT: the grant succeeds (observed October 2026), SHOW GRANTS lists
-- PAYMENTS_DB.WORK_READER among Risk's grants (pending live run), Risk reads
-- BATCHES 2 from WORK (observed October 2026), and the revoke succeeds.
-- The database-role owner decides who receives it, role or user; managed access
-- governs object grants inside a schema and does not apply here.

-- BLOCK: recurring grant audit (OPTIONAL; reporting role with SNOWFLAKE.SECURITY_VIEWER)
-- Pending a live run. ACCOUNT_USAGE latency is up to 2 hours, so run it daily
-- from a scheduled task and alert on any row. Extend the IN list with every role
-- that belongs to the team. Grants of database roles to individual users appear
-- in ACCOUNT_USAGE.GRANTS_TO_USERS; check that view the same way.
SELECT privilege, granted_on, name, table_schema, granted_to, grantee_name,
       granted_by, created_on
FROM snowflake.account_usage.grants_to_roles
WHERE deleted_on IS NULL
  AND table_catalog = 'PAYMENTS_DB'
  AND granted_to <> 'DATABASE_ROLE'
  AND grantee_name NOT IN ('PAYMENTS_ADMIN', 'PAYMENTS_BUILDER', 'PAYMENTS_READER')
ORDER BY created_on DESC;
-- EXPECT: zero rows once revokes have propagated. A row is access to Payments
-- data held outside the team: revoke it and ask the administrator why.
