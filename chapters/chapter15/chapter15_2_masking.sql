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
USE WAREHOUSE BOOK_WH;
USE DATABASE governance_db;

-- -----------------------------------------------------------------------------
-- BLOCK 1 (2.1): unmask role, allow-list function, type-specific policies
-- -----------------------------------------------------------------------------
-- The setup grants the unmask role directly to the lab user, never to a parent role.
USE ROLE GOVERNANCE_OWNER;

-- Expected: SHOW GRANTS OF ROLE pii_reader lists your user and nothing else.

-- Step 2: the allow list, one home for every masking policy.
CREATE FUNCTION governance_db.policies.pii_unmask_ok()
RETURNS BOOLEAN
COMMENT = 'Single source of truth for which roles see unmasked PII'
AS
$$
  IS_ROLE_IN_SESSION('PII_READER')
$$;

-- Function test: FALSE in a plain GOVERNANCE_OWNER session, TRUE once the
-- separately granted PII_READER role is active through secondary roles.
USE SECONDARY ROLES NONE;
SELECT governance_db.policies.pii_unmask_ok() AS unmask_owner_only;
-- Expected: FALSE.
USE SECONDARY ROLES ALL;
SELECT governance_db.policies.pii_unmask_ok() AS unmask_with_pii_role;
-- Expected: TRUE.
USE SECONDARY ROLES NONE;

-- Step 3: the string policy. Fails closed: any category without a branch is
-- fully redacted. Review each branch; never pass through NAME globally.
CREATE MASKING POLICY governance_db.policies.pii_mask_string
AS (val STRING) RETURNS STRING ->
  CASE
    WHEN governance_db.policies.pii_unmask_ok() THEN val
    WHEN val IS NULL THEN NULL
    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_DB.POLICIES.PII_CATEGORY')
         IN ('COUNTRY', 'ADMINISTRATIVE_AREA_1', 'CITY') THEN val
    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_DB.POLICIES.PII_CATEGORY')
         = 'EMAIL'
         THEN REGEXP_REPLACE(val, '^([^@]{1,2})[^@]*@', '\\1***@')
    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_DB.POLICIES.PII_CATEGORY')
         = 'POSTAL_CODE'
         THEN LEFT(val, 3) || '**'
    ELSE '***MASKED***'
  END
COMMENT = 'Tag-driven masking for string PII; unrecognized categories are fully redacted';

-- Step 4: policies for the other data types the tag can land on.
CREATE MASKING POLICY governance_db.policies.pii_mask_number
AS (val NUMBER) RETURNS NUMBER ->
  CASE WHEN governance_db.policies.pii_unmask_ok() THEN val ELSE NULL END;

CREATE MASKING POLICY governance_db.policies.pii_mask_date
AS (val DATE) RETURNS DATE ->
  CASE WHEN governance_db.policies.pii_unmask_ok() THEN val
       ELSE DATE_TRUNC('YEAR', val) END;

-- The chapter points at this twin of the date policy by role: without it a
-- TIMESTAMP_NTZ column the profile classifies would be tagged but unmasked.
CREATE MASKING POLICY governance_db.policies.pii_mask_timestamp
AS (val TIMESTAMP_NTZ) RETURNS TIMESTAMP_NTZ ->
  CASE WHEN governance_db.policies.pii_unmask_ok() THEN val
       ELSE DATE_TRUNC('YEAR', val) END;

-- Expected: every CREATE returns 'successfully created.'

-- -----------------------------------------------------------------------------
-- BLOCK 2 (2.2): bind policies to the tag, THEN attach the profile
-- -----------------------------------------------------------------------------
-- Order is the point: policies on the tag first, profile second, so the first
-- column the profile tags is protected in the same instant.
ALTER TAG governance_db.policies.pii_category SET
    MASKING POLICY governance_db.policies.pii_mask_string,
    MASKING POLICY governance_db.policies.pii_mask_number,
    MASKING POLICY governance_db.policies.pii_mask_date;

-- The script binds the timestamp policy too; the chapter binds three and
-- points here for the fourth. A tag holds one policy per data type.
ALTER TAG governance_db.policies.pii_category SET
    MASKING POLICY governance_db.policies.pii_mask_timestamp;

-- Expected: 'Statement executed successfully.' (fails if two policies share
-- a data type).

-- Attach only to business schemas (automatic scans begin after about an hour).
-- Keep POLICIES and QUALITY outside the scope: classifying MERCHANT_ACCESS.
-- ROLE_NAME as OCCUPATION attaches masking to a row-policy dependency and
-- breaks protected reads and column-based DMFs with error 003542.
ALTER SCHEMA governance_db.customers
    SET CLASSIFICATION_PROFILE = 'governance_db.classification.pii_profile';
ALTER SCHEMA governance_db.merchants
    SET CLASSIFICATION_PROFILE = 'governance_db.classification.pii_profile';
ALTER SCHEMA governance_db.transactions
    SET CLASSIFICATION_PROFILE = 'governance_db.classification.pii_profile';

CALL SYSTEM$CLASSIFY('governance_db.customers.dim_customers',
                     'governance_db.classification.pii_profile');

-- Expected: each ALTER returns 'Statement executed successfully.'; the CALL
-- returns the dry-scan JSON with "tag_applied": true under each
-- recommendation. Privilege errors here mean chapter15_0_setup.sql did not
-- run (EXECUTE AUTO CLASSIFICATION and APPLY TAG on the account).

USE SECONDARY ROLES NONE;
-- Reviewed minimum coverage: classification is a recommendation, not a
-- guarantee. Explicit tags protect these known sensitive fixture columns.
ALTER TABLE governance_db.customers.dim_customers MODIFY COLUMN customer_name
    SET TAG governance_db.policies.pii_category = 'NAME';
ALTER TABLE governance_db.customers.dim_customers MODIFY COLUMN email
    SET TAG governance_db.policies.pii_category = 'EMAIL';
-- Narrow exception for this reviewed synthetic business-name column only.
CREATE MASKING POLICY governance_db.policies.public_merchant_name
AS (val STRING) RETURNS STRING -> val;
ALTER TABLE governance_db.merchants.dim_merchants MODIFY COLUMN merchant_name
    SET MASKING POLICY governance_db.policies.public_merchant_name;
-- Verification: masked as plain GOVERNANCE_OWNER, clear with the unmask role active
-- as a secondary role.
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
SELECT customer_id, customer_name, email, city, postal_code
FROM governance_db.customers.dim_customers
WHERE customer_id = 'CUST-CH12-0007';
USE SECONDARY ROLES ALL;
SELECT customer_id, customer_name, email, city, postal_code
FROM governance_db.customers.dim_customers
WHERE customer_id = 'CUST-CH12-0007';
USE SECONDARY ROLES NONE;

-- Expected, first query: CUSTOMER_ID intact, CUSTOMER_NAME '***MASKED***',
-- EMAIL 'cu***@example.com', CITY in clear, POSTAL_CODE 'NNN**'.
-- Expected, second query: name and 'customer0007@example.com' in clear.

-- Mechanism view (optional): every classified column with its tag values.
-- SELECT column_name, tag_name, tag_value
--   FROM TABLE(governance_db.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
--          'governance_db.customers.dim_customers', 'TABLE'))
--  ORDER BY column_name, tag_name;

-- Real primary-role verification of the unmask branch.
USE ROLE pii_reader;
USE SECONDARY ROLES NONE;
SELECT customer_id, customer_name, email
FROM governance_db.customers.dim_customers
WHERE customer_id = 'CUST-CH12-0007';
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
-- Expected: the same clear name/email as the secondary-role test.

-- Force the false-positive category on the synthetic business-name column to
-- prove the exception's scope rather than relying on an untagged input.
ALTER TABLE governance_db.merchants.dim_merchants MODIFY COLUMN merchant_name
    SET TAG governance_db.policies.pii_category = 'NAME';
SELECT merchant_name FROM governance_db.merchants.dim_merchants LIMIT 3;
SELECT customer_name FROM governance_db.customers.dim_customers LIMIT 3;
-- Expected: merchant names in clear; customer names fully masked.

-- -----------------------------------------------------------------------------
-- BLOCK 3 (2.3): conditional policy for the support desk
-- -----------------------------------------------------------------------------
-- A direct column policy beats the tag policy on the same column. The USING
-- clause hands is_current to the policy from the same row; that column can
-- then never appear in a row access policy signature on this table.
USE ROLE GOVERNANCE_OWNER;

CREATE MASKING POLICY governance_db.policies.email_support_mask
AS (email STRING, is_current BOOLEAN) RETURNS STRING ->
  CASE
    WHEN governance_db.policies.pii_unmask_ok() THEN email
    WHEN IS_ROLE_IN_SESSION('SUPPORT_AGENT') AND is_current THEN email
    WHEN email IS NULL THEN NULL
    ELSE REGEXP_REPLACE(email, '^([^@]{1,2})[^@]*@', '\\1***@')
  END;

ALTER TABLE governance_db.customers.dim_customers MODIFY COLUMN email
    SET MASKING POLICY governance_db.policies.email_support_mask
    USING (email, is_current);

-- Expected: every statement succeeds. POLICY_REFERENCES lists the direct
-- policy on EMAIL beside the tag policies on the other columns:
-- SELECT policy_name, policy_kind, ref_column_name
--   FROM TABLE(governance_db.INFORMATION_SCHEMA.POLICY_REFERENCES(
--          REF_ENTITY_NAME => 'governance_db.customers.dim_customers',
--          REF_ENTITY_DOMAIN => 'TABLE'));

-- Test the actual active-role hierarchy and object grants. POLICY_CONTEXT
-- overrides did not reproduce IS_ROLE_IN_SESSION in the live validation;
-- do not substitute a simulated result for these real-role checks.
USE ROLE support_agent;
USE SECONDARY ROLES NONE;
SELECT customer_id, customer_name, email, is_current
FROM governance_db.customers.dim_customers
WHERE customer_id = 'CUST-CH12-0007' ORDER BY effective_from;
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
-- Exercise the historical branch even when every copied version is current.
-- Copy one clear lab row with a new key, mark the copy closed, then remove it.
-- ALL is intentional only while capturing/copying the unmasked baseline.
USE ROLE governance_owner;
USE SECONDARY ROLES ALL;
SET original_customer_hash = (SELECT HASH_AGG(*) FROM governance_db.customers.dim_customers);
SET historical_test_key = (SELECT MIN(customer_key) - 1 FROM governance_db.customers.dim_customers);
INSERT INTO governance_db.customers.dim_customers
SELECT * REPLACE ($historical_test_key AS customer_key, FALSE AS is_current,
                  DATEADD('DAY', -1, effective_from) AS effective_from,
                  effective_from AS effective_to)
FROM governance_db.customers.dim_customers
WHERE customer_id = 'CUST-CH12-0007' AND is_current LIMIT 1;
USE ROLE support_agent;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) = 1 AND COUNT_IF(NOT is_current AND email LIKE '%***%'
       AND customer_name = '***MASKED***') = 1 AS historical_mask_passed
FROM governance_db.customers.dim_customers
WHERE customer_key = $historical_test_key;
-- Expected: TRUE. The earlier real-role query verifies the current branch.
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
DELETE FROM governance_db.customers.dim_customers
WHERE customer_key = $historical_test_key;
USE SECONDARY ROLES ALL;
SELECT HASH_AGG(*) = $original_customer_hash AS customer_fixture_restored
FROM governance_db.customers.dim_customers;
-- Expected: TRUE; the temporary version is gone and all original values match.
USE SECONDARY ROLES NONE;
