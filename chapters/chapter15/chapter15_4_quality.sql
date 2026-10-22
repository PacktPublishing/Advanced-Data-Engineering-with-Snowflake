-- Chapter 15: Governance, Security, and Data Quality (Packt, 2026)
-- Placeholder convention: book and BOOK_WH are defaults; no SQL placeholders.
-- Run with Snowflake CLI: snow sql -c book -f <this file>.
-- Requires Enterprise Edition, BOOK_WH, and chapter15_0_setup.sql.
-- Lab scope: GOVERNANCE_DB and the five reserved lab roles only.
-- USERADMIN creates roles; GOVERNANCE_OWNER owns lab objects under SYSADMIN;
-- ACCOUNTADMIN grants account privileges only in setup. No writes to GOLD_DB.
-- Full run order and execution evidence: README.md and VALIDATION.md.

USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;
USE DATABASE governance_db;
-- Step 1: explicitly set the lab cadence before adding DMFs. The default
-- schedule is hourly; five minutes shortens the lab wait. For loaded facts,
-- use TRIGGER_ON_CHANGES or a cron after the load. Each run bills serverless credits (Data Quality Monitoring). A new
-- schedule takes about ten minutes to become effective.
USE ROLE GOVERNANCE_OWNER;
ALTER TABLE governance_db.transactions.fact_transactions
    SET DATA_METRIC_SCHEDULE = '5 MINUTE';

-- Expected: 'Statement executed successfully.'
-- SHOW PARAMETERS LIKE 'DATA_METRIC_SCHEDULE' IN TABLE governance_db.transactions.fact_transactions;

-- Step 2: four system DMFs. ROW_COUNT takes an empty column list; FRESHNESS
-- measures last DML age with ON (); transaction_ts is TIMESTAMP_NTZ.
-- No freshness expectation is appropriate for this static training fixture.
ALTER TABLE governance_db.transactions.fact_transactions
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (customer_id)
    EXPECTATION customer_present (VALUE = 0);

ALTER TABLE governance_db.transactions.fact_transactions
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (transaction_id)
    EXPECTATION unique_payment (VALUE = 0);

ALTER TABLE governance_db.transactions.fact_transactions
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
    EXPECTATION not_truncated (VALUE > 0);

ALTER TABLE governance_db.transactions.fact_transactions
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON ();

-- Expected: 'Statement executed successfully.' four times. Preview option
-- (not run here): ... ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
-- ANOMALY_DETECTION = TRUE; needs about two weeks of history.

-- Step 3: custom referential DMF (two table arguments, distinct column names).
CREATE DATA METRIC FUNCTION governance_db.quality.orphan_merchant_count(
    facts TABLE (fact_merchant_id STRING),
    dims  TABLE (dim_merchant_id  STRING))
RETURNS NUMBER
COMMENT = 'Fact rows whose merchant_id has no row in the merchant dimension'
AS
$$
  SELECT COUNT(*)
    FROM facts
   WHERE fact_merchant_id NOT IN (SELECT dim_merchant_id FROM dims
                                   WHERE dim_merchant_id IS NOT NULL)
$$;

-- Expected: 'Function ORPHAN_MERCHANT_COUNT successfully created.'
-- Ad hoc call (returns 0 on the stock fixture):
SELECT governance_db.quality.orphan_merchant_count(
         (SELECT merchant_id FROM governance_db.transactions.fact_transactions),
         (SELECT merchant_id FROM governance_db.merchants.dim_merchants)) AS orphans;

-- Step 4: attach with the second table argument and an expectation.
ALTER TABLE governance_db.transactions.fact_transactions
    ADD DATA METRIC FUNCTION governance_db.quality.orphan_merchant_count
    ON (merchant_id, TABLE (governance_db.merchants.dim_merchants (merchant_id)))
    EXPECTATION no_orphan_merchants (VALUE = 0);

-- Expected: 'Statement executed successfully.' Then five associations:
SELECT metric_name, ref_arguments, schedule_status
  FROM TABLE(governance_db.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
         REF_ENTITY_NAME => 'governance_db.transactions.fact_transactions',
         REF_ENTITY_DOMAIN => 'TABLE'));

-- Expected: five rows; STARTED or briefly STARTED_AND_PENDING_SCHEDULE_UPDATE.

-- -----------------------------------------------------------------------------
-- BLOCK 2 (4.3): notifications, planted row, verdicts, cleanup
-- -----------------------------------------------------------------------------
-- Direct email delivery to the signed-in user; no duplicate integration path.
-- Setup gives LAB_STATE.RECIPIENT an owner-only direct masking policy so
-- automatic classification cannot redact the operational address for its owner.
-- DATA_QUALITY_MONITORING_SETTINGS is labelled Preview in ALTER DATABASE
-- as checked on 2026-09-08: https://docs.snowflake.com/en/sql-reference/sql/alter-database
SET notification_sql = (
  SELECT 'ALTER DATABASE governance_db SET DATA_QUALITY_MONITORING_SETTINGS = '
       || CHR(39) || 'notification:\n  enabled: TRUE\n  email_recipients: ['
       || TO_JSON(TO_VARIANT(recipient))
       || ']\n  cooldown_hours: 4\n  metadata_included: TRUE' || CHR(39)
  FROM governance_db.quality.lab_state);
EXECUTE IMMEDIATE $notification_sql;

-- Record an incident boundary. CTAS deliberately omitted the source RELY keys.
INSERT INTO governance_db.transactions.fact_transactions
    (transaction_id, customer_id, merchant_id, amount, transaction_ts,
     category, channel, status)
VALUES
    ('TXN-PLANT-001', 'CUST-CH12-0007', 'MERCH-GHOST',
     42.00, CURRENT_TIMESTAMP(), 'retail', 'web', 'COMPLETED');
UPDATE governance_db.quality.lab_state SET planted_at = CURRENT_TIMESTAMP();

-- Reusable bounded wait. Query both the association name and the incident's
-- timestamp so a previous run cannot satisfy this run's verification.
CREATE PROCEDURE governance_db.quality.await_orphan_result(want_violation BOOLEAN)
RETURNS STRING LANGUAGE SQL EXECUTE AS CALLER AS
$$
DECLARE
  boundary TIMESTAMP_LTZ;
  deadline TIMESTAMP_LTZ DEFAULT DATEADD('MINUTE', 30, CURRENT_TIMESTAMP());
  found NUMBER DEFAULT 0;
  suspended NUMBER DEFAULT 0;
  timed_out EXCEPTION (-20154, 'No matching scheduled result within 30 minutes. Inspect DMF status; planted evidence is retained until verified or teardown.');
  invalid_metric EXCEPTION (-20157, 'A quality metric is suspended. Inspect DATA_METRIC_FUNCTION_REFERENCES and policy dependencies, including classification tags on MERCHANT_ACCESS. The planted row is retained.');
BEGIN
  SELECT IFF(:want_violation, planted_at, deleted_at) INTO :boundary
    FROM governance_db.quality.lab_state;
  WHILE (CURRENT_TIMESTAMP() < deadline) DO
    SELECT COUNT(*) INTO :suspended
    FROM TABLE(governance_db.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_NAME => 'governance_db.transactions.fact_transactions',
        REF_ENTITY_DOMAIN => 'TABLE'))
    WHERE schedule_status LIKE 'SUSPENDED%';
    IF (suspended > 0) THEN RAISE invalid_metric; END IF;
    SELECT COUNT(*) INTO :found
    FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
    WHERE table_database = 'GOVERNANCE_DB'
      AND table_schema = 'TRANSACTIONS' AND table_name = 'FACT_TRANSACTIONS'
      AND metric_database = 'GOVERNANCE_DB'
      AND metric_schema = 'QUALITY' AND metric_name = 'ORPHAN_MERCHANT_COUNT'
      AND expectation_name = 'NO_ORPHAN_MERCHANTS'
      AND scheduled_time > :boundary AND measurement_time > :boundary
      AND expectation_violated = :want_violation
      AND value::NUMBER = IFF(:want_violation, 1, 0);
    IF (found > 0) THEN RETURN 'Observed scheduled orphan result: ' || want_violation; END IF;
    CALL SYSTEM$WAIT(30);
  END WHILE;
  RAISE timed_out;
END;
$$;
CALL governance_db.quality.await_orphan_result(TRUE);

SELECT measurement_time, metric_name, expectation_name, value, expectation_violated
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE table_database = 'GOVERNANCE_DB' AND table_schema = 'TRANSACTIONS'
  AND table_name = 'FACT_TRANSACTIONS'
ORDER BY measurement_time DESC, metric_name LIMIT 12;
-- Expected: orphan 1 / TRUE; other expectations remain FALSE.
-- Server-side notification status is distinct from arrival in an inbox.

-- This statement is reached only after a fresh scheduled violation was seen.
DELETE FROM governance_db.transactions.fact_transactions
 WHERE transaction_id = 'TXN-PLANT-001';
UPDATE governance_db.quality.lab_state SET deleted_at = CURRENT_TIMESTAMP();
CALL governance_db.quality.await_orphan_result(FALSE);
-- Expected: later scheduled orphan value 0 / FALSE. Do not substitute an
-- ad hoc call for either scheduled observation.
