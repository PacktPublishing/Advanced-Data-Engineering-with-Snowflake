-- Chapter 18: OPTIONAL fleet usage query (section "Governing the account fleet").
-- Reference only: works in any organization, through one of the two paths below.
-- Path A (organization account): USE ROLE GLOBALORGADMIN. The schema is
--   available by default; GLOBALORGADMIN owns it.
-- Path B (ORGADMIN-enabled regular account): USE ROLE ORGADMIN. Requires a
--   one-time ACCOUNTADMIN grant before the first run:
--     USE ROLE ACCOUNTADMIN;
--     GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE ORGADMIN;
--   The ORGADMIN role also needs USAGE on a warehouse.
-- The core lab does not create or need this.
-- Validation: official Snowflake docs checked October 2026; SQL run live October 2026.
-- Placeholders: none. ORGANIZATION_USAGE latency is up to 2 hours.

-- BLOCK: billed credits per account
-- Use GLOBALORGADMIN in an organization account, or ORGADMIN in a regular account.
USE ROLE ORGADMIN;
SELECT account_name, region,
       SUM(credits_billed) AS billed_credits
FROM snowflake.organization_usage.metering_daily_history
WHERE usage_date >= DATEADD(day, -8, CURRENT_DATE())
  AND usage_date < DATEADD(day, -1, CURRENT_DATE())
GROUP BY account_name, region
ORDER BY billed_credits DESC;
-- EXPECT: one row per account that consumed credits in the seven settled days.
-- Compare the list with the account registry: an account absent from the
-- registry, or a registry entry with no owner, is a finding.
