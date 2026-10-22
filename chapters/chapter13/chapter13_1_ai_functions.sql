-- =============================================================================
-- Chapter 13, Section 2: Enriching and Classifying Text at Scale with
--                        Cortex AI Functions
-- Independent after chapter13_0_setup.sql; no other section file needed.
--
-- Prerequisites:
--   - chapter13_0_setup.sql (schema + 40-ticket fixture).
--   - Role with SNOWFLAKE.CORTEX_USER (granted in setup) and usage on BOOK_WH.
--   - Tested August 2026. AI_FILTER / AI_AGG / AI_SUMMARIZE_AGG GA since
--     January 2026. Model updated 2026-10-02: mistral-large2 went legacy on
--     2026-08-12 (end of life 2026-10-14), so AI_COMPLETE and AI_COUNT_TOKENS
--     now use llama3.3-70b (in-region on the major AWS and Azure regions).
--     Run SHOW CORTEX BASE MODELS to check lifecycle_status before you pin
--     a model, and re-check the extraction output after any model change.
--
-- Cost note: every statement below that calls an AI function bills per token.
-- The fixture keeps this to a rounding error; do not point these statements
-- at a large table without running the AI_COUNT_TOKENS estimate at the end.
-- Role convention: SYSADMIN throughout (object DDL only).
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;
USE SCHEMA support;

-- -----------------------------------------------------------------------------
-- 2.2 Classifying Tickets with AI_CLASSIFY
-- Taxonomy stored as data: every classifying statement reads this one row,
-- so adding a category is an UPDATE here, not an edit to N statements.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE gold_db.support.ticket_taxonomy AS
SELECT [
    {'label': 'billing dispute',
     'description': 'Charged twice, wrong amount, or a charge the customer does not recognize'},
    {'label': 'failed payment',
     'description': 'A payment attempt that declined, timed out, or shows as pending'},
    {'label': 'refund status',
     'description': 'Asking where a promised or expected refund is'},
    {'label': 'account access',
     'description': 'Login, lockout, or credential problems'},
    {'label': 'feature question',
     'description': 'How to use a product capability, no money in dispute'}
] AS categories;

-- Classify all 40 tickets once and persist (pay the token once, read a column
-- forever). Expect ten to twenty seconds: each row is a model call.
CREATE OR REPLACE TABLE gold_db.support.ticket_enriched AS
SELECT t.*,
       AI_CLASSIFY(
           t.body,
           (SELECT categories
              FROM gold_db.support.ticket_taxonomy),
           {'task_description':
            'Classify a payment-platform support ticket by the problem the customer reports'}
       ):labels[0]::VARCHAR AS category
FROM gold_db.support.support_tickets t;

-- Score against the 12 hand labels. Expect 11 or 12 matches; if lower,
-- sharpen the category descriptions (overlap is the usual cause).
SELECT COUNT_IF(category = expected_category) AS matches,
       COUNT(*) AS labeled
FROM gold_db.support.ticket_enriched
WHERE expected_category IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2.3 Filtering and Routing with AI_FILTER
-- Cheap predicates first (status), model predicate last. Expect 3 tickets:
-- TKT-CH13-009, TKT-CH13-026, TKT-CH13-033.
-- -----------------------------------------------------------------------------
SELECT ticket_id, merchant_category, opened_at
FROM gold_db.support.ticket_enriched
WHERE status = 'OPEN'
  AND AI_FILTER(PROMPT(
      'The customer states they will file a chargeback, contact a lawyer, or take the dispute to their bank. Do not flag mere frustration, a pending charge, a declined payment, or a delayed refund: {0}',
      body))
ORDER BY opened_at;

-- -----------------------------------------------------------------------------
-- 2.4 Extracting Structured Fields with AI_COMPLETE
-- JSON schema constrains the output; only requested_action is required
-- because amount and merchant may legitimately be absent.
-- -----------------------------------------------------------------------------
SELECT ticket_id,
       AI_COMPLETE(
           model  => 'llama3.3-70b',
           prompt => PROMPT(
             'Extract the disputed amount, the merchant named, and the action the customer requests: {0}',
             body),
           response_format => {
             'type': 'json',
             'schema': {'type': 'object',
                        'properties': {
                            'disputed_amount':  {'type': 'number'},
                            'merchant_name':    {'type': 'string'},
                            'requested_action': {'type': 'string'}},
                        'required': ['requested_action']}}
       ) AS extracted
FROM gold_db.support.ticket_enriched
WHERE category = 'billing dispute';

-- -----------------------------------------------------------------------------
-- 2.5 Summarizing Themes with AI_AGG and AI_SUMMARIZE_AGG
-- -----------------------------------------------------------------------------
-- One row per merchant category; Travel should lead with duplicate charges.
SELECT merchant_category,
       AI_AGG(body,
              'List the three most common problems customers report, one short phrase each')
           AS top_problems
FROM gold_db.support.ticket_enriched
GROUP BY merchant_category;

-- One-row weekly digest for the last full fixture week.
SELECT AI_SUMMARIZE_AGG(body) AS weekly_digest
FROM gold_db.support.ticket_enriched
WHERE opened_at >= '2026-06-22'
  AND opened_at <  '2026-06-29';

-- Automated metadata creation: draft a catalog description from the data,
-- then paste the result into COMMENT ON TABLE if you like it.
SELECT AI_AGG(body,
              'Write a one-sentence data catalog description of this content')
           AS table_comment_draft
FROM gold_db.support.support_tickets;

-- -----------------------------------------------------------------------------
-- 2.6 Making Enrichment Incremental
-- Stream + hourly task: tokens are paid per new ticket, never per run.
-- Change tracking also pre-pays the Cortex Search requirement in Section 3.
-- -----------------------------------------------------------------------------
ALTER TABLE gold_db.support.support_tickets
    SET CHANGE_TRACKING = TRUE;

CREATE OR REPLACE STREAM gold_db.support.ticket_stream
    ON TABLE gold_db.support.support_tickets;

-- Single-statement consumer: the stream offset advances when this INSERT
-- commits, so each ticket is classified once and only once.
CREATE OR REPLACE TASK gold_db.support.enrich_new_tickets
    WAREHOUSE = BOOK_WH
    SCHEDULE = '60 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('gold_db.support.ticket_stream')
AS
INSERT INTO gold_db.support.ticket_enriched
SELECT s.ticket_id, s.txn_id, s.merchant_category, s.channel,
       s.opened_at, s.status, s.expected_category, s.body,
       s.resolution,
       AI_CLASSIFY(s.body,
           (SELECT categories
              FROM gold_db.support.ticket_taxonomy),
           {'task_description':
            'Classify a payment-platform support ticket by the problem the customer reports'}
       ):labels[0]::VARCHAR
FROM gold_db.support.ticket_stream s
WHERE s.METADATA$ACTION = 'INSERT';

ALTER TASK gold_db.support.enrich_new_tickets RESUME;

-- Price a job before running it: function name first (lowercase), then
-- model, then input. Token count times the current per-million-token rate
-- from the Service Consumption Table.
SELECT SUM(AI_COUNT_TOKENS('ai_complete', 'llama3.3-70b', body)) AS input_tokens
FROM gold_db.support.support_tickets;

-- -----------------------------------------------------------------------------
-- Section validation set
-- -----------------------------------------------------------------------------
-- 1) Enriched table complete: expect 40 rows, 0 null categories.
SELECT COUNT(*)                    AS rows_enriched,
       COUNT_IF(category IS NULL)  AS null_categories
FROM gold_db.support.ticket_enriched;

-- 2) Task exists and is started. Quote lowercase RESULT_SCAN columns.
SHOW TASKS LIKE 'enrich_new_tickets' IN SCHEMA gold_db.support;
SELECT "name", "state", "schedule"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- 3) End-to-end smoke test: insert one ticket, run the task now, expect
--    rows_enriched to read 41 afterward.
INSERT INTO gold_db.support.support_tickets VALUES
('TKT-CH13-041', 'TXN-88901', 'retail', 'chat',
 '2026-06-28 10:00:00', 'OPEN', NULL,
 'Charged for an extended warranty I removed from the cart.', NULL);
EXECUTE TASK gold_db.support.enrich_new_tickets;
SELECT SYSTEM$WAIT(15);
SELECT COUNT(*) AS rows_enriched
FROM gold_db.support.ticket_enriched;
