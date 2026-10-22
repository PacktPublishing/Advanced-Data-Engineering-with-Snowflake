-- Chapter 15 post-lab behavior checks; run after scripts 0-5, before teardown.
-- Uses the book connection and BOOK_WH; no SQL placeholders.
-- Creates and drops one lab-only probe table to exercise all four mask types.
-- Source GOLD_DB is read only. Stop on errors; every PASSED value must be TRUE.
-- Historical-email fixture coverage is in chapter15_2_masking.sql itself.
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;
USE DATABASE governance_db;
SET expected_customers = (SELECT COUNT(*) FROM gold_db.customers.dim_customers);
SET expected_customer_hash = (SELECT HASH_AGG(*) FROM gold_db.customers.dim_customers);
SET expected_current_email_hash = (SELECT HASH_AGG(customer_key, email) FROM gold_db.customers.dim_customers WHERE is_current);
SET expected_payments = (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions);
SET expected_merchants = (SELECT COUNT(*) FROM gold_db.merchants.dim_merchants);
SET expected_portal_rows = (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions WHERE merchant_id IN ('MERCH-CH12-07','MERCH-CH12-08'));
SELECT 'owner_masked_names' AS test, COUNT(*) = $expected_customers AND COUNT_IF(customer_name <> '***MASKED***') = 0 AS passed FROM customers.dim_customers;
SELECT 'owner_full_fact' AS test, COUNT(*) = $expected_payments AS passed FROM transactions.fact_transactions;
SELECT 'merchant_exception' AS test, COUNT(*) = $expected_merchants AND COUNT_IF(merchant_name = '***MASKED***') = 0 AS passed FROM merchants.dim_merchants;
SELECT 'merchant_name_tag' AS test, SYSTEM$GET_TAG('GOVERNANCE_DB.POLICIES.PII_CATEGORY','GOVERNANCE_DB.MERCHANTS.DIM_MERCHANTS.MERCHANT_NAME','COLUMN') = 'NAME' AS passed;
USE SECONDARY ROLES ALL;
SELECT 'secondary_pii_clear_hash' AS test, HASH_AGG(*) = $expected_customer_hash AS passed FROM customers.dim_customers;
USE SECONDARY ROLES NONE;
CREATE TABLE quality.validation_masking_probe(v STRING, n NUMBER, d DATE, t TIMESTAMP_NTZ);
INSERT INTO quality.validation_masking_probe VALUES ('private',123,'2024-08-20','2024-08-20 13:14:15'),(NULL,NULL,NULL,NULL);
ALTER TABLE quality.validation_masking_probe MODIFY COLUMN v SET TAG policies.pii_category = 'UNRECOGNIZED';
ALTER TABLE quality.validation_masking_probe MODIFY COLUMN n SET TAG policies.pii_category = 'IDENTIFIER';
ALTER TABLE quality.validation_masking_probe MODIFY COLUMN d SET TAG policies.pii_category = 'DATE_OF_BIRTH';
ALTER TABLE quality.validation_masking_probe MODIFY COLUMN t SET TAG policies.pii_category = 'DATE_OF_BIRTH';
GRANT USAGE ON SCHEMA quality TO ROLE pii_reader;
GRANT SELECT ON TABLE quality.validation_masking_probe TO ROLE pii_reader;
SELECT 'type_masks_and_nulls' AS test, COUNT(*) = 2 AND COUNT_IF(v = '***MASKED***') = 1 AND COUNT_IF(n IS NULL) = 2 AND COUNT_IF(d = '2024-01-01'::DATE) = 1 AND COUNT_IF(t = '2024-01-01 00:00:00'::TIMESTAMP_NTZ) = 1 AND COUNT_IF(v IS NULL AND d IS NULL AND t IS NULL) = 1 AS passed FROM quality.validation_masking_probe;
USE ROLE pii_reader;
USE SECONDARY ROLES NONE;
SELECT 'primary_pii_clear_hash' AS test, HASH_AGG(*) = $expected_customer_hash AS passed FROM customers.dim_customers;
SELECT 'type_masks_authorized' AS test, COUNT_IF(v = 'private' AND n = 123 AND d = '2024-08-20'::DATE AND t = '2024-08-20 13:14:15'::TIMESTAMP_NTZ) = 1 AND COUNT_IF(v IS NULL AND n IS NULL AND d IS NULL AND t IS NULL) = 1 AS passed FROM quality.validation_masking_probe;
USE ROLE support_agent;
USE SECONDARY ROLES NONE;
SELECT 'support_current_emails' AS test, HASH_AGG(customer_key, email) = $expected_current_email_hash AND COUNT_IF(customer_name <> '***MASKED***') = 0 AS passed, COUNT(*) AS current_versions, COUNT_IF(email IS NULL) AS null_emails FROM customers.dim_customers WHERE is_current;
USE ROLE merchant_portal;
USE SECONDARY ROLES NONE;
SELECT 'portal_fact_scope' AS test, COUNT(*) = $expected_portal_rows AND COUNT(DISTINCT merchant_id) = 2 AND COUNT_IF(merchant_id NOT IN ('MERCH-CH12-07','MERCH-CH12-08')) = 0 AS passed, COUNT(*) AS visible_rows FROM transactions.fact_transactions;
SELECT 'portal_view_scope' AS test, COUNT(*) = $expected_portal_rows AND COUNT(DISTINCT merchant_id) = 2 AND COUNT_IF(merchant_id NOT IN ('MERCH-CH12-07','MERCH-CH12-08')) = 0 AS passed, COUNT(*) AS visible_rows FROM transactions.star_transactions;
USE ROLE unentitled_reader;
USE SECONDARY ROLES NONE;
SELECT 'denied_customer_pii' AS test, COUNT_IF(customer_name <> '***MASKED***' OR email NOT LIKE '%***%') = 0 AS passed FROM customers.dim_customers;
SELECT 'denied_fact_scope' AS test, COUNT(*) = 0 AS passed FROM transactions.fact_transactions;
SELECT 'denied_view_scope' AS test, COUNT(*) = 0 AS passed FROM transactions.star_transactions;
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
DROP TABLE quality.validation_masking_probe;
SELECT 'entitlement_table_has_no_policy_dependencies' AS test, COUNT(*)=0 AS passed
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME=>'governance_db.policies.merchant_access',REF_ENTITY_DOMAIN=>'TABLE'));
SELECT 'metric_associations' AS test, COUNT(*)=5 AND COUNT_IF(schedule_status='STARTED')=5 AND COUNT_IF(data_quality_notification_status='ENABLED')=5 AS passed
FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(REF_ENTITY_NAME=>'governance_db.transactions.fact_transactions',REF_ENTITY_DOMAIN=>'TABLE'));
SELECT 'scheduled_failure_and_recovery' AS test,
       COUNT_IF(expectation_violated AND value::NUMBER=1 AND scheduled_time > s.planted_at AND measurement_time > s.planted_at)>0
       AND COUNT_IF(NOT expectation_violated AND value::NUMBER=0 AND scheduled_time > s.deleted_at AND measurement_time > s.deleted_at)>0 AS passed
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS e
CROSS JOIN quality.lab_state s
WHERE table_database='GOVERNANCE_DB' AND table_schema='TRANSACTIONS' AND table_name='FACT_TRANSACTIONS'
  AND metric_database='GOVERNANCE_DB' AND metric_schema='QUALITY' AND metric_name='ORPHAN_MERCHANT_COUNT'
  AND expectation_name='NO_ORPHAN_MERCHANTS';
SELECT 'scheduled_system_column_metrics' AS test,
       COUNT(DISTINCT metric_name)=2
       AND COUNT_IF(value::NUMBER<>0 OR expectation_violated)=0 AS passed
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS e
CROSS JOIN quality.lab_state s
WHERE table_database='GOVERNANCE_DB' AND table_schema='TRANSACTIONS' AND table_name='FACT_TRANSACTIONS'
  AND metric_database='SNOWFLAKE' AND metric_schema='CORE'
  AND metric_name IN ('NULL_COUNT','DUPLICATE_COUNT')
  AND scheduled_time > s.planted_at AND measurement_time > s.planted_at;
SELECT 'reviewed_channel_comment' AS test, COUNT_IF(column_name='PROCESSING_CHANNEL' AND comment='Refund intake route: portal or support; NULL means not captured')=1 AS passed
FROM INFORMATION_SCHEMA.COLUMNS WHERE table_schema='TRANSACTIONS' AND table_name='FACT_REFUNDS';
SELECT 'preserved_refund_grain' AS test, comment='Grain: one row per refund event, identified by refund_id.' AS passed
FROM INFORMATION_SCHEMA.TABLES WHERE table_schema='TRANSACTIONS' AND table_name='FACT_REFUNDS';
