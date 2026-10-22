-- Chapter 15: Governance, Security, and Data Quality (Packt, 2026)
-- Placeholder convention: book and BOOK_WH are defaults; no SQL placeholders.
-- Run with Snowflake CLI: snow sql -c book -f <this file>.
-- Requires Enterprise Edition, BOOK_WH, and chapter15_0_setup.sql.
-- Lab scope: GOVERNANCE_DB and the five reserved lab roles only.
-- USERADMIN creates roles; GOVERNANCE_OWNER owns lab objects under SYSADMIN;
-- ACCOUNTADMIN grants account privileges only in setup. No writes to GOLD_DB.
-- Full run order and execution evidence: README.md and VALIDATION.md.

USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
USE ROLE GOVERNANCE_OWNER;
USE WAREHOUSE BOOK_WH;
USE DATABASE governance_db;

-- -----------------------------------------------------------------------------
-- BLOCK 1 (step 1): entitlement table, portal role, minimal grants.
-- The GOVERNANCE_OWNER wildcard row goes in BEFORE the policy exists: a protected
-- table with no matching row returns zero rows to everyone, owner included.
-- -----------------------------------------------------------------------------
USE ROLE GOVERNANCE_OWNER;
CREATE TABLE governance_db.policies.merchant_access (
    role_name   STRING NOT NULL,
    merchant_id STRING NOT NULL,
    granted_on  DATE   DEFAULT CURRENT_DATE()
) COMMENT = 'Which role may read which merchant. * means every merchant';

INSERT INTO governance_db.policies.merchant_access (role_name, merchant_id) VALUES
    ('GOVERNANCE_OWNER',            '*'),
    ('MERCHANT_PORTAL',  'MERCH-CH12-07'),
    ('MERCHANT_PORTAL',  'MERCH-CH12-08');

-- Expected: 3 rows inserted. Setup already granted the portal's database,
-- schema, table/view, and warehouse access. GOVERNANCE_OWNER cannot grant access
-- to BOOK_WH, which it does not own and has no grant option on.

-- Step 2: the policy. Argument named txn_merchant_id on purpose: an
-- unqualified merchant_id inside the subquery would bind to the mapping
-- table's own column and make the comparison always true.
CREATE ROW ACCESS POLICY governance_db.policies.merchant_rows
AS (txn_merchant_id STRING) RETURNS BOOLEAN ->
  EXISTS (
    SELECT 1
      FROM governance_db.policies.merchant_access m
     WHERE IS_ROLE_IN_SESSION(m.role_name)
       AND (m.merchant_id = txn_merchant_id OR m.merchant_id = '*')
  )
COMMENT = 'Tenant filter for the merchant portal; entitlements live in merchant_access';

-- Expected: 'Row access policy MERCHANT_ROWS successfully created.'

-- Step 3: attach. One row access policy per table; change the rule later
-- with ALTER ROW ACCESS POLICY ... SET BODY ->.
ALTER TABLE governance_db.transactions.fact_transactions
    ADD ROW ACCESS POLICY governance_db.policies.merchant_rows ON (merchant_id);

-- Expected: 'Statement executed successfully.'

-- Step 4: verification on the fact and on the star view. The portal role
-- was granted SELECT on the view in block 1; the view runs with its owner's
-- privileges while the base-table policy evaluates in the session's context.
SELECT COUNT(*) AS visible_rows
  FROM governance_db.transactions.fact_transactions;

USE ROLE merchant_portal;
USE SECONDARY ROLES NONE;
SELECT merchant_id, COUNT(*) AS payments
  FROM governance_db.transactions.fact_transactions
 GROUP BY merchant_id ORDER BY merchant_id;

SELECT merchant_id, merchant_city, month_start,
       SUM(IFF(status = 'COMPLETED', amount, 0)) AS captured
  FROM governance_db.transactions.star_transactions
 GROUP BY merchant_id, merchant_city, month_start
 ORDER BY merchant_id, month_start;
USE ROLE GOVERNANCE_OWNER;

-- Expected: 50,024 as GOVERNANCE_OWNER; as MERCHANT_PORTAL two rows
-- (MERCH-CH12-07, MERCH-CH12-08, about 1,250 payments each on the stock
-- fixture), then one row per month for the same two storefronts from the
-- star view and no other merchant.

USE ROLE unentitled_reader;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) AS denied_rows FROM governance_db.transactions.fact_transactions;
SELECT COUNT(*) AS denied_view_rows FROM governance_db.transactions.star_transactions;
-- Expected: 0 for both, despite SELECT privileges.
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
