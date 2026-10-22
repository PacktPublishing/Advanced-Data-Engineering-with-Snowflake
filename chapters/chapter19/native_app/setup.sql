-- Chapter 19 Native App installation/upgrade script.
-- Called by Snowflake inside application context; never run as an ordinary worksheet.
-- Prerequisites: package SHARED_DATA and staged streamlit/app.py.
-- Validation: documentation checked September 2026; not installed live.
-- No reader-specific placeholders. No USE ROLE: execution identity is the application.

CREATE APPLICATION ROLE IF NOT EXISTS app_reader;
CREATE OR ALTER VERSIONED SCHEMA app_public;
CREATE OR REPLACE VIEW app_public.daily_metrics AS
  SELECT event_date, merchant_id, attempts,
         approved_attempts, approved_amount_usd
  FROM shared_data.daily_metrics;
CREATE OR REPLACE STREAMLIT app_public.dashboard
  FROM '/streamlit'
  MAIN_FILE = '/app.py';
GRANT USAGE ON SCHEMA app_public
  TO APPLICATION ROLE app_reader;
GRANT SELECT ON VIEW app_public.daily_metrics
  TO APPLICATION ROLE app_reader;
GRANT USAGE ON STREAMLIT app_public.dashboard
  TO APPLICATION ROLE app_reader;
