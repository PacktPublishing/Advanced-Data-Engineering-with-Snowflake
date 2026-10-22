-- =============================================================================
-- Chapter 13, Section 3: Building Hybrid Retrieval and RAG Pipelines with
--                        Cortex Search
-- Independent after chapter13_0_setup.sql. The Python query path for this
-- section is chapter13_2_search_client.py.
--
-- Prerequisites:
--   - chapter13_0_setup.sql (fixture) run first.
--   - Role with SNOWFLAKE.CORTEX_USER, CREATE CORTEX SEARCH SERVICE on
--     gold_db.support, and usage on BOOK_WH.
--   - Tested August 2026. Cortex Search GA; automatic serving suspension on
--     inactivity still preview, so run chapter13_teardown.sql when done:
--     serving bills per GB-month while the service is up.
--
-- Role convention: SYSADMIN throughout (object DDL only).
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;
USE SCHEMA support;

-- -----------------------------------------------------------------------------
-- 3.1 Preparing the Knowledge Base
-- Resolved tickets only (the value is the fix), body + resolution in one
-- searchable column, PII redacted at write time so the index never holds
-- raw names, emails, or card fragments. Change tracking is required by the
-- search service for incremental refresh.
-- -----------------------------------------------------------------------------
-- AI_REDACT returns VARCHAR on success but OBJECT when a row errors, so CTAS
-- infers VARIANT. Cortex Search requires a text column: cast it.
CREATE OR REPLACE TABLE gold_db.support.ticket_kb AS
SELECT ticket_id,
       merchant_category,
       channel,
       opened_at,
       AI_REDACT(body || ' Resolution: ' || resolution)::VARCHAR
           AS kb_text
FROM gold_db.support.support_tickets
WHERE status = 'RESOLVED';

ALTER TABLE gold_db.support.ticket_kb
    SET CHANGE_TRACKING = TRUE;

-- Expect 28 rows, and placeholders such as [NAME] / [EMAIL] in kb_text.
SELECT COUNT(*) AS kb_rows FROM gold_db.support.ticket_kb;
-- Chapter 3.1 step 2: one redacted row (placeholders incl. [PAYMENT_CARD_DATA]).
SELECT kb_text FROM gold_db.support.ticket_kb LIMIT 1;

-- -----------------------------------------------------------------------------
-- 3.2 Creating the Search Service
-- PRIMARY KEY => incremental refresh (only changed rows re-embed).
-- ATTRIBUTES  => filterable columns, not searched.
-- WAREHOUSE   => refreshes only; serving is managed compute.
-- EMBEDDING_MODEL omitted: the English default fits this knowledge base.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE gold_db.support.ticket_search
    ON kb_text
    PRIMARY KEY (ticket_id)
    ATTRIBUTES merchant_category, channel
    WAREHOUSE = BOOK_WH
    TARGET_LAG = '1 hour'
AS (
    SELECT ticket_id, merchant_category, channel, kb_text
    FROM gold_db.support.ticket_kb
);

-- Chapter 3.2 step 2: confirm the service exists (expect one row, TICKET_SEARCH).
SHOW CORTEX SEARCH SERVICES IN SCHEMA gold_db.support;

-- Consumers need usage on the service (plus db/schema usage).
-- GRANT USAGE ON CORTEX SEARCH SERVICE gold_db.support.ticket_search
--     TO ROLE support_analyst;  -- role created in chapter13_4_agent.sql

-- -----------------------------------------------------------------------------
-- 3.3 Querying the Service (SQL smoke test)
-- Semantic hit on purpose: the query says "charged twice", the ticket says
-- "duplicate capture". Expect TKT-CH13-001 first.
-- -----------------------------------------------------------------------------
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'gold_db.support.ticket_search',
        '{
           "query": "customer charged twice for one booking",
           "columns": ["ticket_id", "kb_text", "merchant_category"],
           "filter": {"@eq": {"merchant_category": "travel"}},
           "limit": 3
         }'
    )
):results AS results;

-- -----------------------------------------------------------------------------
-- 3.4 Assembling a Grounded Answer (RAG in one statement)
-- The instruction restricts the model to the context, requires citations,
-- and permits "the context does not answer this".
-- -----------------------------------------------------------------------------
WITH hits AS (
    SELECT PARSE_JSON(
        SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
            'gold_db.support.ticket_search',
            '{"query": "how do we handle duplicate charges",
              "columns": ["ticket_id", "kb_text"],
              "limit": 3}'
        )):results AS r
)
SELECT AI_COMPLETE(
    model  => 'llama3.3-70b',
    prompt => 'Answer the question using only the context. '
           || 'Cite ticket ids you used. If the context does '
           || 'not answer the question, say so. Question: how '
           || 'do we handle duplicate charges? Context: '
           || r::VARCHAR
) AS grounded_answer
FROM hits;

-- Refusal path: the knowledge base knows nothing about crypto settlement, so a
-- grounded pipeline must say so instead of inventing an answer.
WITH hits AS (
    SELECT PARSE_JSON(
        SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
            'gold_db.support.ticket_search',
            '{"query": "cryptocurrency settlement policy",
              "columns": ["ticket_id", "kb_text"],
              "limit": 3}'
        )):results AS r
)
SELECT AI_COMPLETE(
    model  => 'llama3.3-70b',
    prompt => 'Answer the question using only the context. '
           || 'Cite ticket ids you used. If the context does '
           || 'not answer the question, say so. Question: what '
           || 'is our cryptocurrency settlement policy? Context: '
           || r::VARCHAR
) AS refusal_check
FROM hits;

-- -----------------------------------------------------------------------------
-- 3.5 Operating the Service + section validation set
-- -----------------------------------------------------------------------------
-- 1) Service state: serving/indexing state, target lag, source definition.
DESCRIBE CORTEX SEARCH SERVICE gold_db.support.ticket_search;

-- 2) Retrieval sanity: the Travel query above returns TKT-CH13-001 in its
--    top results. Re-run the 3.3 statement and confirm.

-- 3) Freshness contract: insert a resolved row into ticket_kb, wait past
--    TARGET_LAG (or check DESCRIBE for the refresh), and confirm it is
--    searchable.
