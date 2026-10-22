-- Chapter 15: Governance, Security, and Data Quality (Packt, 2026)
-- Placeholder convention: book and BOOK_WH are defaults; no SQL placeholders.
-- Run with Snowflake CLI: snow sql -c book -f <this file>.
-- Requires Enterprise Edition, BOOK_WH, and the four Chapter 14 gold tables.
-- Lab scope: GOVERNANCE_DB and the five reserved lab roles only.
-- USERADMIN creates roles; GOVERNANCE_OWNER owns lab objects under SYSADMIN;
-- ACCOUNTADMIN grants account privileges only in setup. No writes to GOLD_DB.
-- Full run order and execution evidence: README.md and VALIDATION.md.

-- Run once. Name collisions fail BEFORE creating anything. To rerun, use
-- the guarded teardown first. Source data is the Chapter 14 gold fixture.
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;
ALTER SESSION SET QUERY_TAG = 'chapter15_validation';
SHOW DATABASES LIKE 'GOVERNANCE_DB';
EXECUTE IMMEDIATE $$
DECLARE collision EXCEPTION (-20150, 'GOVERNANCE_DB already exists. Review it; do not overwrite it.');
BEGIN
  IF (EXISTS (SELECT 1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())))) THEN
    RAISE collision;
  END IF;
END;
$$;
SHOW ROLES;
EXECUTE IMMEDIATE $$
DECLARE collision EXCEPTION (-20151, 'A role name reserved by this lab already exists. Review it; do not overwrite it.');
BEGIN
  IF (EXISTS (SELECT 1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
      WHERE "name" IN ('GOVERNANCE_OWNER','PII_READER','SUPPORT_AGENT',
                       'MERCHANT_PORTAL','UNENTITLED_READER'))) THEN
    RAISE collision;
  END IF;
END;
$$;
-- Compile all four source references before creating the lab.
SELECT (SELECT COUNT(*) FROM gold_db.customers.dim_customers) AS customers,
       (SELECT COUNT(*) FROM gold_db.merchants.dim_merchants) AS merchants,
       (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions) AS payments,
       (SELECT COUNT(*) FROM gold_db.transactions.fact_refunds) AS refunds;
-- Capture the signed-in user's address without a hard-coded recipient.
SHOW USERS;
SET lab_email = (SELECT "email" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
                  WHERE "name" = CURRENT_USER());
-- Capture the quoted user name before USERADMIN clears the active warehouse.
SET lab_user = (SELECT '"' || REPLACE(CURRENT_USER(), '"', '""') || '"');
USE ROLE USERADMIN;
CREATE ROLE governance_owner COMMENT = 'Chapter 15 isolated governance lab v3';
CREATE ROLE pii_reader COMMENT = 'Chapter 15 isolated governance lab v3';
CREATE ROLE support_agent COMMENT = 'Chapter 15 isolated governance lab v3';
CREATE ROLE merchant_portal COMMENT = 'Chapter 15 isolated governance lab v3';
CREATE ROLE unentitled_reader COMMENT = 'Chapter 15 isolated governance lab v3';
GRANT ROLE governance_owner TO ROLE SYSADMIN;
SET grant_stmt = 'GRANT ROLE governance_owner TO USER ' || $lab_user;
EXECUTE IMMEDIATE $grant_stmt;
SET grant_stmt = 'GRANT ROLE pii_reader TO USER ' || $lab_user;
EXECUTE IMMEDIATE $grant_stmt;
SET grant_stmt = 'GRANT ROLE support_agent TO USER ' || $lab_user;
EXECUTE IMMEDIATE $grant_stmt;
SET grant_stmt = 'GRANT ROLE merchant_portal TO USER ' || $lab_user;
EXECUTE IMMEDIATE $grant_stmt;
SET grant_stmt = 'GRANT ROLE unentitled_reader TO USER ' || $lab_user;
EXECUTE IMMEDIATE $grant_stmt;
USE ROLE ACCOUNTADMIN;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE governance_owner;
GRANT APPLY TAG ON ACCOUNT TO ROLE governance_owner;
GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE governance_owner;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE governance_owner;
GRANT EXECUTE AUTO CLASSIFICATION ON ACCOUNT TO ROLE governance_owner;
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE governance_owner;
GRANT MANAGE DATA QUALITY ON ACCOUNT TO ROLE governance_owner;
GRANT DATABASE ROLE SNOWFLAKE.CLASSIFICATION_ADMIN TO ROLE governance_owner;
GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE governance_owner;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE governance_owner;
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE governance_owner;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE governance_owner;
GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE governance_owner;
GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE pii_reader;
GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE support_agent;
GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE merchant_portal;
GRANT USAGE ON WAREHOUSE BOOK_WH TO ROLE unentitled_reader;
GRANT USAGE ON DATABASE gold_db TO ROLE governance_owner;
GRANT USAGE ON SCHEMA gold_db.customers TO ROLE governance_owner;
GRANT USAGE ON SCHEMA gold_db.merchants TO ROLE governance_owner;
GRANT USAGE ON SCHEMA gold_db.transactions TO ROLE governance_owner;
GRANT SELECT ON TABLE gold_db.customers.dim_customers TO ROLE governance_owner;
GRANT SELECT ON TABLE gold_db.merchants.dim_merchants TO ROLE governance_owner;
GRANT SELECT ON TABLE gold_db.transactions.fact_transactions TO ROLE governance_owner;
GRANT SELECT ON TABLE gold_db.transactions.fact_refunds TO ROLE governance_owner;
USE ROLE governance_owner;
USE WAREHOUSE BOOK_WH;
CREATE DATABASE governance_db COMMENT = 'Chapter 15 isolated governance lab v3';
CREATE SCHEMA governance_db.customers;
CREATE SCHEMA governance_db.merchants;
CREATE SCHEMA governance_db.transactions;
CREATE SCHEMA governance_db.policies;
CREATE SCHEMA governance_db.classification;
CREATE SCHEMA governance_db.quality;
-- CTAS copies values, not Chapter 14's RELY constraints or policy attachments.
-- Never substitute CLONE here: the quality lab deliberately breaks a key.
CREATE TABLE governance_db.customers.dim_customers AS SELECT * FROM gold_db.customers.dim_customers;
CREATE TABLE governance_db.merchants.dim_merchants AS SELECT * FROM gold_db.merchants.dim_merchants;
CREATE TABLE governance_db.transactions.fact_transactions AS SELECT * FROM gold_db.transactions.fact_transactions;
CREATE TABLE governance_db.transactions.fact_refunds AS SELECT * FROM gold_db.transactions.fact_refunds;
COMMENT ON TABLE governance_db.transactions.fact_refunds
  IS 'Grain: one row per refund event, identified by refund_id.';
CREATE VIEW governance_db.transactions.star_transactions AS
SELECT f.*, m.merchant_city, DATE_TRUNC('MONTH', f.transaction_ts)::DATE AS month_start
FROM governance_db.transactions.fact_transactions f
JOIN governance_db.merchants.dim_merchants m ON f.merchant_id = m.merchant_id;
CREATE TABLE governance_db.quality.lab_state (
  recipient STRING, planted_at TIMESTAMP_LTZ, deleted_at TIMESTAMP_LTZ);
-- Classification can tag this operational email. A direct policy keeps the
-- lab owner able to configure delivery while other roles receive NULL.
CREATE MASKING POLICY governance_db.policies.lab_recipient_mask
AS (val STRING) RETURNS STRING ->
  CASE WHEN IS_ROLE_IN_SESSION('GOVERNANCE_OWNER') THEN val ELSE NULL END;
ALTER TABLE governance_db.quality.lab_state MODIFY COLUMN recipient
  SET MASKING POLICY governance_db.policies.lab_recipient_mask;
INSERT INTO governance_db.quality.lab_state(recipient) SELECT $lab_email;
GRANT USAGE ON DATABASE governance_db TO ROLE pii_reader;
GRANT USAGE ON SCHEMA governance_db.customers TO ROLE pii_reader;
GRANT USAGE ON SCHEMA governance_db.transactions TO ROLE pii_reader;
GRANT USAGE ON SCHEMA governance_db.merchants TO ROLE pii_reader;
GRANT SELECT ON TABLE governance_db.customers.dim_customers TO ROLE pii_reader;
GRANT SELECT ON TABLE governance_db.transactions.fact_transactions TO ROLE pii_reader;
GRANT SELECT ON VIEW governance_db.transactions.star_transactions TO ROLE pii_reader;
GRANT SELECT ON TABLE governance_db.merchants.dim_merchants TO ROLE pii_reader;
GRANT USAGE ON DATABASE governance_db TO ROLE support_agent;
GRANT USAGE ON SCHEMA governance_db.customers TO ROLE support_agent;
GRANT USAGE ON SCHEMA governance_db.transactions TO ROLE support_agent;
GRANT USAGE ON SCHEMA governance_db.merchants TO ROLE support_agent;
GRANT SELECT ON TABLE governance_db.customers.dim_customers TO ROLE support_agent;
GRANT SELECT ON TABLE governance_db.transactions.fact_transactions TO ROLE support_agent;
GRANT SELECT ON VIEW governance_db.transactions.star_transactions TO ROLE support_agent;
GRANT SELECT ON TABLE governance_db.merchants.dim_merchants TO ROLE support_agent;
GRANT USAGE ON DATABASE governance_db TO ROLE merchant_portal;
GRANT USAGE ON SCHEMA governance_db.customers TO ROLE merchant_portal;
GRANT USAGE ON SCHEMA governance_db.transactions TO ROLE merchant_portal;
GRANT USAGE ON SCHEMA governance_db.merchants TO ROLE merchant_portal;
GRANT SELECT ON TABLE governance_db.customers.dim_customers TO ROLE merchant_portal;
GRANT SELECT ON TABLE governance_db.transactions.fact_transactions TO ROLE merchant_portal;
GRANT SELECT ON VIEW governance_db.transactions.star_transactions TO ROLE merchant_portal;
GRANT SELECT ON TABLE governance_db.merchants.dim_merchants TO ROLE merchant_portal;
GRANT USAGE ON DATABASE governance_db TO ROLE unentitled_reader;
GRANT USAGE ON SCHEMA governance_db.customers TO ROLE unentitled_reader;
GRANT USAGE ON SCHEMA governance_db.transactions TO ROLE unentitled_reader;
GRANT USAGE ON SCHEMA governance_db.merchants TO ROLE unentitled_reader;
GRANT SELECT ON TABLE governance_db.customers.dim_customers TO ROLE unentitled_reader;
GRANT SELECT ON TABLE governance_db.transactions.fact_transactions TO ROLE unentitled_reader;
GRANT SELECT ON VIEW governance_db.transactions.star_transactions TO ROLE unentitled_reader;
GRANT SELECT ON TABLE governance_db.merchants.dim_merchants TO ROLE unentitled_reader;
SELECT COUNT(*) AS lab_payments FROM governance_db.transactions.fact_transactions;
-- Expected on the stock fixture: 50024. Different source totals carry through;
-- later checks compare the copied baseline, not a hard-coded universal count.
