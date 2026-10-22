-- Chapter 15: Governance, Security, and Data Quality (Packt, 2026)
-- Placeholder convention: book and BOOK_WH are defaults; no SQL placeholders.
-- Run with Snowflake CLI: snow sql -c book -f <this file>.
-- Handles partial setup and repeated cleanup; database/role markers are checked.
-- Lab scope: GOVERNANCE_DB and the five reserved lab roles only.
-- USERADMIN creates roles; GOVERNANCE_OWNER owns lab objects under SYSADMIN;
-- ACCOUNTADMIN grants account privileges only in setup. No writes to GOLD_DB.
-- Full run order and execution evidence: README.md and VALIDATION.md.

-- Destructive only to this dedicated lab. Run after any successful subset.
-- Guards inspect ALL reserved names before dropping any object; no blanket
-- exception swallowing and no shared-table policy/tag/comment removal.
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
SHOW DATABASES LIKE 'GOVERNANCE_DB';
EXECUTE IMMEDIATE $$
DECLARE unsafe EXCEPTION (-20155, 'Database is not marked as the Chapter 15 lab. Teardown refused.');
BEGIN
  IF (EXISTS (SELECT 1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
      WHERE COALESCE("comment", '') <> 'Chapter 15 isolated governance lab v3')) THEN
    RAISE unsafe;
  END IF;
END;
$$;
SHOW ROLES;
EXECUTE IMMEDIATE $$
DECLARE unsafe EXCEPTION (-20156, 'A reserved role is not marked as the Chapter 15 lab. Teardown refused.');
BEGIN
  IF (EXISTS (SELECT 1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
      WHERE "name" IN ('GOVERNANCE_OWNER','PII_READER','SUPPORT_AGENT',
                       'MERCHANT_PORTAL','UNENTITLED_READER')
        AND COALESCE("comment", '') <> 'Chapter 15 isolated governance lab v3')) THEN
    RAISE unsafe;
  END IF;
END;
$$;
USE ROLE SYSADMIN;
DROP DATABASE IF EXISTS governance_db;
-- Dropping the lab removes its profile, metrics, schedules, policies, comments,
-- and incident rows. No tag or policy was attached outside this database.
USE ROLE USERADMIN;
DROP ROLE IF EXISTS unentitled_reader;
DROP ROLE IF EXISTS merchant_portal;
DROP ROLE IF EXISTS support_agent;
DROP ROLE IF EXISTS pii_reader;
DROP ROLE IF EXISTS governance_owner;
USE ROLE ACCOUNTADMIN;
SHOW DATABASES LIKE 'GOVERNANCE_DB';
SHOW ROLES;
SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
 WHERE "name" IN ('GOVERNANCE_OWNER','PII_READER','SUPPORT_AGENT',
                  'MERCHANT_PORTAL','UNENTITLED_READER');
-- Expected: no lab database and no rows from the reserved-role query. A role
-- of the same name that predates the lab blocks setup and is never dropped here.
