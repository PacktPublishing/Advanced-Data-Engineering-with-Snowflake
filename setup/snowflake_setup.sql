-- =============================================================================
-- Snowflake Setup for: Advanced Snowflake Data Engineering
--
-- Run this in Snowsight (or SnowSQL) on a fresh trial account.
--
-- This script is deliberately split into role blocks. Only ONE statement in it
-- genuinely requires ACCOUNTADMIN (attaching the network policy to the account).
-- Everything else runs as SYSADMIN or SECURITYADMIN, which is how you would
-- provision this in a real environment. Watch the USE ROLE statements as you go
-- and note why each block needs the role it uses.
-- =============================================================================


-- =============================================================================
-- BLOCK 1 — SYSADMIN: databases, schemas, warehouse
--
-- SYSADMIN holds CREATE DATABASE and CREATE WAREHOUSE on the account by
-- default, so no elevated role is needed for any of this.
-- =============================================================================

USE ROLE SYSADMIN;

-- Utility database — houses shared objects (network rules, MCP servers, etc.)

CREATE OR REPLACE DATABASE UTIL
    COMMENT = 'Shared utilities — Advanced Snowflake DE Book';

CREATE OR REPLACE SCHEMA UTIL.SECURITY
    COMMENT = 'Network rules and policies';

CREATE OR REPLACE SCHEMA UTIL.AI
    COMMENT = 'MCP servers and AI integrations';

-- Clinical database used by the Chapter 2 Iceberg exercises.
-- Chapter 2 sets its worksheet context to CLINICAL_DATA.PATIENT_RECORDS, so
-- these two objects must exist before you run the first CREATE ICEBERG TABLE.

CREATE OR REPLACE DATABASE CLINICAL_DATA
    COMMENT = 'MedCore clinical data — Chapter 2 Iceberg exercises';

CREATE OR REPLACE SCHEMA CLINICAL_DATA.PATIENT_RECORDS
    COMMENT = 'Patient encounter tables — Chapter 2';

-- Warehouse for all book exercises

CREATE WAREHOUSE IF NOT EXISTS BOOK_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Shared warehouse — Advanced Snowflake DE Book';

-- Network rule — created by SYSADMIN because SYSADMIN owns UTIL.SECURITY, and
-- the schema owner holds CREATE NETWORK RULE on it.
-- Replace the IP address below with your own. Find it at https://api.ipify.org

CREATE NETWORK RULE IF NOT EXISTS UTIL.SECURITY.nr_book_cli_access
    TYPE = IPV4
    VALUE_LIST = ('<REPLACE: your-ip>/32')
    MODE = INGRESS
    COMMENT = 'CLI/MCP IP allowlist for book exercises';

-- MCP server for Cursor IDE integration — SYSADMIN owns UTIL.AI

CREATE MCP SERVER IF NOT EXISTS UTIL.AI.book_sql_exec_server
    FROM SPECIFICATION $$
    tools:
      - title: "SQL Execution Tool"
        name: "sql_exec_tool"
        type: "SYSTEM_EXECUTE_SQL"
        description: "Execute SQL queries for the Snowflake Data Engineering book exercises."
    $$;


-- =============================================================================
-- BLOCK 2 — SECURITYADMIN: the network policy object
--
-- CREATE NETWORK POLICY is an account-level privilege that SECURITYADMIN holds
-- by default. Creating the policy and attaching it are separate acts requiring
-- different roles, which is a useful thing to notice.
-- =============================================================================

USE ROLE SECURITYADMIN;

CREATE NETWORK POLICY IF NOT EXISTS book_network_policy
    ALLOWED_NETWORK_RULE_LIST = ('UTIL.SECURITY.nr_book_cli_access')
    COMMENT = 'Network policy for book CLI/MCP access';


-- =============================================================================
-- BLOCK 3 — ACCOUNTADMIN: the only statements that truly need it
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- !! CAUTION !!
-- This locks the entire account to the single IP you set above. If your IP
-- changes (new network, VPN, DHCP lease), you lock yourself out of the account.
-- To recover you need a second admin session from an allowed IP, or Snowflake
-- Support. On a shared or long-lived account, attach the policy to your user
-- instead of the account:
--     ALTER USER <your_user> SET NETWORK_POLICY = book_network_policy;
-- Skip this statement entirely if you do not need PAT/CLI/MCP access.

ALTER ACCOUNT SET NETWORK_POLICY = book_network_policy;

-- Iceberg needs two account-level privileges that only ACCOUNTADMIN holds by
-- default. Granting them to SYSADMIN is what lets the Chapter 2 exercises run
-- as SYSADMIN rather than as ACCOUNTADMIN. In a real deployment these would go
-- to a dedicated provisioning role rather than to SYSADMIN.

GRANT CREATE EXTERNAL VOLUME ON ACCOUNT TO ROLE SYSADMIN;
GRANT CREATE INTEGRATION     ON ACCOUNT TO ROLE SYSADMIN;


-- =============================================================================
-- BLOCK 4 — Your own user: Programmatic Access Token (PAT)
--
-- No special role is required. A human user (TYPE = PERSON) needs no privileges
-- to manage a PAT on themselves, and omitting the user name targets the active
-- user. Run this as whichever role you are already using.
--
-- !! The token is shown ONCE in the output — copy it immediately !!
-- =============================================================================

ALTER USER ADD PROGRAMMATIC ACCESS TOKEN book_cursor_pat
    DAYS_TO_EXPIRY = 30
    COMMENT = 'PAT for Cursor MCP — Snowflake DE Book';


-- =============================================================================
-- Verify
-- =============================================================================

USE ROLE SYSADMIN;

SHOW MCP SERVERS IN SCHEMA UTIL.AI;
SHOW DATABASES LIKE 'CLINICAL_DATA';
SHOW SCHEMAS IN DATABASE CLINICAL_DATA;

SELECT CURRENT_ACCOUNT() AS account,
       CURRENT_USER()    AS username,
       CURRENT_ROLE()    AS role,
       CURRENT_REGION()  AS region;
