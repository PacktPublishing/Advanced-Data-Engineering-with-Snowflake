-- =========================================================================
-- Chapter 6, Section 5.4: daily quality report posted to Slack
-- =========================================================================
-- REVIEW ONLY. Every statement below creates or replaces an account object.
-- Read it, adjust the schema names and the Slack channel, and run it by hand in
-- a worksheet as a role that can create integrations and secrets (creating an
-- external access integration and a network rule needs ACCOUNTADMIN, or a role
-- with CREATE INTEGRATION granted). Nothing in the repository executes this file.
--
-- It builds the alerting layer the chapter describes: a task that runs at 6:00
-- a.m. local time, reads the Elementary failure tables, and posts a summary of
-- failed runs, failed tests, and freshness misses to a Slack channel.
--
-- The webhook URL is held in a Snowflake SECRET, never inline in the procedure
-- body and never committed. Replace the placeholder once, in the worksheet.
-- =========================================================================

-- 1. Somewhere to keep the monitoring objects.
USE ROLE SYSADMIN;

CREATE SCHEMA IF NOT EXISTS ops_db.monitoring;

-- 2. Egress rule and secret for the Slack webhook. Only Slack's hook host is
--    allowed, on 443, so the procedure cannot reach anything else.
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE NETWORK RULE ops_db.monitoring.slack_webhook_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('hooks.slack.com:443');

-- Paste the webhook into SECRET_STRING in the worksheet. Do not commit the value.
CREATE OR REPLACE SECRET ops_db.monitoring.slack_webhook_url
    TYPE = GENERIC_STRING
    SECRET_STRING = '<https://hooks.slack.com/services/PASTE/YOUR/WEBHOOK>';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION slack_webhook_integration
    ALLOWED_NETWORK_RULES = (ops_db.monitoring.slack_webhook_rule)
    ALLOWED_AUTHENTICATION_SECRETS = (ops_db.monitoring.slack_webhook_url)
    ENABLED = TRUE;

GRANT USAGE ON INTEGRATION slack_webhook_integration TO ROLE SYSADMIN;

-- 3. The procedure. It reads the Elementary tables the dbt package writes, so
--    install Elementary first (see docs.elementary-data.com). Elementary lands
--    its tables in "<your target schema>_elementary"; adjust ELEMENTARY_SCHEMA
--    below to match your deployment before running this.
USE ROLE SYSADMIN;

CREATE OR REPLACE PROCEDURE ops_db.monitoring.post_slack_summary()
    RETURNS STRING
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    PACKAGES = ('snowflake-snowpark-python', 'requests')
    HANDLER = 'main'
    EXTERNAL_ACCESS_INTEGRATIONS = (slack_webhook_integration)
    SECRETS = ('webhook' = ops_db.monitoring.slack_webhook_url)
AS
$$
import _snowflake
import requests

ELEMENTARY_SCHEMA = "silver_db.customers_elementary"

# Failed tests and failed models from the last 24 hours, plus any source whose
# freshness check errored. One row per problem, newest first.
FAILURE_QUERY = f"""
    SELECT 'test' AS kind,
           test_name AS name,
           status,
           detected_at AS occurred_at
    FROM {ELEMENTARY_SCHEMA}.elementary_test_results
    WHERE status IN ('fail', 'error')
      AND detected_at >= DATEADD('hour', -24, CURRENT_TIMESTAMP())

    UNION ALL

    SELECT 'model' AS kind,
           name,
           status,
           generated_at AS occurred_at
    FROM {ELEMENTARY_SCHEMA}.dbt_run_results
    WHERE status IN ('error', 'fail')
      AND generated_at >= DATEADD('hour', -24, CURRENT_TIMESTAMP())

    ORDER BY occurred_at DESC
"""


def main(session):
    rows = session.sql(FAILURE_QUERY).collect()

    if not rows:
        # Staying quiet on a clean night keeps the channel signal-only.
        return "no failures in the last 24 hours; nothing posted"

    lines = [f"*TechFlow nightly data quality: {len(rows)} problem(s)*"]
    for row in rows:
        lines.append(
            f"- `{row['KIND']}` {row['NAME']}: {row['STATUS']} at {row['OCCURRED_AT']}"
        )

    response = requests.post(
        _snowflake.get_generic_secret_string("webhook"),
        json={"text": "\n".join(lines)},
        timeout=30,
    )
    response.raise_for_status()
    return f"posted {len(rows)} problem(s) to Slack"
$$;

-- 4. The 6:00 a.m. task. Created suspended; resume it once a manual CALL of the
--    procedure has posted a message you are happy with.
CREATE OR REPLACE TASK ops_db.monitoring.daily_quality_report
    WAREHOUSE = BOOK_WH
    SCHEDULE = 'USING CRON 0 6 * * * America/New_York'
    AS
    CALL ops_db.monitoring.post_slack_summary();

-- Smoke-test first, then resume:
--   CALL ops_db.monitoring.post_slack_summary();
--   ALTER TASK ops_db.monitoring.daily_quality_report RESUME;
