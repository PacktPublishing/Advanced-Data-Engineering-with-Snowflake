-- Chapter 19: Semantic view, Cortex Agent, and consumer grants
-- Independent optional section after common setup; do not run every service by default.
-- Prerequisites: common setup and chapter19_1_bi.sql (DAILY_METRICS); Cortex availability per CORTEX_ENABLED_CROSS_REGION
-- Validation: documentation checked October 2026; every block run live on the author's sandbox account on 2026-10-24,
-- including the latest_source_update metric and tool_not_accessible: reject (HTTP 403 TOOL_NOT_ACCESSIBLE for NO_DATA_READER).
-- Placeholder convention: <REPLACE: description> only for reader-specific values.
-- Roles: USERADMIN creates roles; SYSADMIN owns lab objects; ACCOUNTADMIN only grants account privileges.
-- Stop on any error. CREATE statements deliberately fail on existing lab tables/services.

-- ACCOUNT ACCESS BLOCK. Does not alter cross-region inference or PUBLIC grants.
USE ROLE ACCOUNTADMIN;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE BI_READER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE NO_DATA_READER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE SYSADMIN;

-- SEMANTIC-VIEW BLOCK.
USE ROLE SYSADMIN;
USE WAREHOUSE BUILD_WH;
CREATE SEMANTIC VIEW
  ANALYTICS_DB.SERVING.PAYMENT_METRICS
  TABLES (
    d AS ANALYTICS_DB.SERVING.DAILY_METRICS
      PRIMARY KEY (event_date, merchant_id)
  )
  DIMENSIONS (
    d.event_date AS d.event_date,
    d.merchant_id AS d.merchant_id
  )
  METRICS (
    d.attempt_count AS SUM(d.attempts),
    d.approved_count AS SUM(d.approved_attempts),
    d.approved_volume_usd AS SUM(d.approved_amount_usd),
    d.approval_rate AS SUM(d.approved_attempts)
      / NULLIF(SUM(d.attempts), 0),
    d.latest_source_update AS MAX(d.source_updated_at)
  )
  COMMENT = 'UTC merchant-day metrics. USD. Approval rate is a fraction.';

-- CONSUMER-GRANT BLOCK. BI_READER already reads DAILY_METRICS (chapter19_1_bi.sql) and is
-- never granted PAYMENT_ATTEMPTS, so the agent reaches merchant-day totals and nothing below them.
-- The agent's generated SQL reads DAILY_METRICS columns directly, so it relies on that grant too.
GRANT SELECT ON SEMANTIC VIEW ANALYTICS_DB.SERVING.PAYMENT_METRICS
  TO ROLE BI_READER;

-- SEMANTIC VERIFICATION: expect 12, 7, 675.00, approximately 0.583333, and the latest load time.
USE ROLE BI_READER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BI_WH;
SELECT * FROM SEMANTIC_VIEW(
  ANALYTICS_DB.SERVING.PAYMENT_METRICS
  METRICS d.attempt_count, d.approved_count,
          d.approved_volume_usd, d.approval_rate,
          d.latest_source_update
);

-- AGENT-DEFINITION BLOCK.
USE ROLE SYSADMIN;
CREATE AGENT ANALYTICS_DB.SERVING.PAYMENT_ANALYST
FROM SPECIFICATION $$
instructions:
  response: >-
    State the UTC date range, currency, and metric definition.
    Ask for clarification when dates or measures are ambiguous.
    Report missing data instead of inventing a cause.
orchestration:
  tool_not_accessible: reject
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: payment_metrics
      description: >-
        Analyze payment attempts, approvals, approved USD
        volume, and approval rate by UTC date and merchant.
tool_resources:
  payment_metrics:
    semantic_view: ANALYTICS_DB.SERVING.PAYMENT_METRICS
    execution_environment:
      type: warehouse
      warehouse: BI_WH
$$;

-- AGENT-USAGE GRANT. Restricted role gets agent usage without reporting-data grants.
GRANT USAGE ON AGENT ANALYTICS_DB.SERVING.PAYMENT_ANALYST
  TO ROLE BI_READER;
GRANT USAGE ON AGENT ANALYTICS_DB.SERVING.PAYMENT_ANALYST
  TO ROLE NO_DATA_READER;

USE ROLE BI_READER;
USE SECONDARY ROLES NONE;
SHOW AGENTS LIKE 'PAYMENT_ANALYST' IN SCHEMA ANALYTICS_DB.SERVING;
-- Expect one agent. Test prompts and negative identity in acceptance.md;
-- chapter19_4_chat_client.py repeats both identities over the REST API.
-- Do not run the agent as SYSADMIN to validate the consumer permission path.
