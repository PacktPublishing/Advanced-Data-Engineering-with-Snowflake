-- =====================================================================
-- Chapter 10, Section 1.1: Managing objects idempotently with CREATE OR ALTER
-- =====================================================================
-- This is the versioned artifact executed straight from Git in Section 1.2
-- via EXECUTE IMMEDIATE FROM @techflow_repo/.../native/warehouses.sql.
--
-- CREATE OR ALTER describes the desired end state, not an action:
--   * absent object  -> created
--   * present object -> altered in place (history and grants intact)
-- so the same file is safe to run repeatedly and converges the object to
-- this definition no matter what state it started in.
-- =====================================================================

-- NOTE: INITIALLY_SUSPENDED is a create-time-only property. Including it in a
-- CREATE OR ALTER fails on the ALTER path with "Property 'INITIALLY_SUSPENDED'
-- cannot be changed in CREATE OR ALTER" once the warehouse exists, which would
-- defeat the whole point of a re-runnable script. It is omitted here so the
-- statement is idempotent on both the create and the alter path.
CREATE OR ALTER WAREHOUSE BOOK_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Transform compute for the TechFlow pipeline';

-- Confirm the current size and settings, whether created or altered.
SHOW WAREHOUSES LIKE 'BOOK_WH';
