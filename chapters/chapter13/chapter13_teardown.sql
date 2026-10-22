-- =============================================================================
-- Chapter 13 teardown — removes everything Chapter 13 created, and nothing
-- else. No DROP ... CASCADE anywhere: every object is named explicitly, so
-- a typo cannot take an earlier chapter's work with it.
--
-- Order matters: task first (stop new work), then the search service (it
-- bills per GB-month while serving), then the agent, then tables, then the
-- chapter-owned schema with RESTRICT as the final safety check.
-- Role convention: SYSADMIN for objects; ACCOUNTADMIN blocks noted.
-- =============================================================================

USE ROLE SYSADMIN;
USE DATABASE gold_db;
USE SCHEMA support;

-- Stop and drop the enrichment task, then its stream.
ALTER TASK IF EXISTS gold_db.support.enrich_new_tickets SUSPEND;
DROP TASK IF EXISTS gold_db.support.enrich_new_tickets;
DROP STREAM IF EXISTS gold_db.support.ticket_stream;

-- The serving meter stops when the service is dropped.
DROP CORTEX SEARCH SERVICE IF EXISTS gold_db.support.ticket_search;

-- CoWork curation cleanup: only if your account added the agent to a CoWork
-- object in chapter13_4_agent.sql (errors otherwise, hence commented).
-- ALTER SNOWFLAKE INTELLIGENCE snowflake_intelligence_object_default
--     REMOVE AGENT gold_db.support.techflow_assistant;

DROP AGENT IF EXISTS gold_db.support.techflow_assistant;

-- Optional quota from chapter13_0_setup.sql (Section 1.3). Uncomment if you
-- created it, or DROP SCHEMA ... RESTRICT below will refuse to run.
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS gold_db.support.ai_spend_quota;

-- Chapter tables.
DROP TABLE IF EXISTS gold_db.support.ticket_kb;
DROP TABLE IF EXISTS gold_db.support.ticket_enriched;
DROP TABLE IF EXISTS gold_db.support.ticket_taxonomy;
DROP TABLE IF EXISTS gold_db.support.support_tickets;

-- RESTRICT: errors if anything unexpected still lives here, which is the
-- point. Investigate before forcing anything.
DROP SCHEMA IF EXISTS gold_db.support RESTRICT;

-- Demo role (USERADMIN owns roles).
USE ROLE USERADMIN;
DROP ROLE IF EXISTS support_analyst;

-- ACCOUNTADMIN, optional: disable guardrails only if nothing else in the
-- account relies on them (account-level setting, not chapter-scoped).
-- USE ROLE ACCOUNTADMIN;
-- ALTER ACCOUNT UNSET AI_SETTINGS;
