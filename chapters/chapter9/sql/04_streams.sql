-- =========================================================================
-- Chapter 9, Section 2.1: Capturing change with streams
-- =========================================================================
-- Creates an append-only stream on the raw landing table and inspects it.
-- SHOW_INITIAL_ROWS = FALSE means it starts empty.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- 2.1a  Create the stream
CREATE OR REPLACE STREAM raw_db.streaming.new_txn_stream
    ON TABLE raw_db.streaming.raw_transactions
    APPEND_ONLY = TRUE
    SHOW_INITIAL_ROWS = FALSE;

-- 2.1b  Inspect pending rows (should be empty right after creation)
SELECT raw_data:transaction_id::STRING                AS transaction_id,
       TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2) AS amount,
       METADATA$ACTION
FROM raw_db.streaming.new_txn_stream
LIMIT 20;
