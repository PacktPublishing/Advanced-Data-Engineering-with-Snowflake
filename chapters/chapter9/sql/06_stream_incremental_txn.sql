-- =========================================================================
-- Chapter 9, Section 2.3: Building a stream-fed incremental load
-- =========================================================================
-- Demonstrates consuming a stream inside an explicit transaction so the
-- offset and multiple writes commit together atomically.
--
-- NOTE: The triggered task from 05 must be SUSPENDED before running this,
-- otherwise it will consume the stream first. This script suspends it,
-- inserts test rows, then runs the transactional load.
-- =========================================================================

USE ROLE CH09_ORCHESTRATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;

-- Suspend the triggered task so it does not race with this script
ALTER TASK ops_db.pipelines.process_new_transactions SUSPEND;

-- Recreate the stream so it picks up the test rows below
CREATE OR REPLACE STREAM raw_db.streaming.new_txn_stream
    ON TABLE raw_db.streaming.raw_transactions
    APPEND_ONLY = TRUE
    SHOW_INITIAL_ROWS = FALSE;

-- Insert test rows (including one negative-amount row for the reject path)
INSERT INTO raw_db.streaming.raw_transactions (raw_data)
SELECT OBJECT_CONSTRUCT(
    'transaction_id', 'TXN-STREAM-TEST-' || SEQ4(),
    'merchant',       OBJECT_CONSTRUCT('id', 'merch_stream_test'),
    'customer',       OBJECT_CONSTRUCT('id', 'cust_stream_test'),
    'amount',         IFF(SEQ4() = 3, -50.00, 100.00 + SEQ4()),
    'currency',       'USD',
    'timestamp',      CURRENT_TIMESTAMP(),
    'status',         'COMPLETED',
    'metadata',       OBJECT_CONSTRUCT('channel', 'TEST', 'risk_score', 0)
)
FROM TABLE(GENERATOR(ROWCOUNT => 5));

-- 2.3  Transactional multi-target stream consumption
BEGIN;

INSERT INTO silver_db.transactions.transactions_clean
SELECT
    raw_data:transaction_id::STRING                  AS transaction_id,
    UPPER(raw_data:merchant.id::STRING)              AS merchant_id,
    UPPER(raw_data:currency::STRING)                 AS currency,
    TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2)   AS amount,
    TRY_TO_TIMESTAMP_NTZ(raw_data:timestamp::STRING) AS transaction_ts,
    raw_data:status::STRING                          AS status
FROM raw_db.streaming.new_txn_stream
WHERE METADATA$ACTION = 'INSERT';

INSERT INTO silver_db.transactions.rejected_transactions (transaction_id, amount, reject_reason)
SELECT
    raw_data:transaction_id::STRING                AS transaction_id,
    TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2) AS amount,
    'NEGATIVE_AMOUNT'                              AS reject_reason
FROM raw_db.streaming.new_txn_stream
WHERE METADATA$ACTION = 'INSERT'
  AND TRY_TO_DECIMAL(raw_data:amount::STRING, 12, 2) < 0;

COMMIT;

-- Verify: stream should now be empty (offset advanced)
SELECT COUNT(*) AS pending_after_commit
FROM raw_db.streaming.new_txn_stream;

-- Verify: rejected_transactions should have the negative-amount row
SELECT * FROM silver_db.transactions.rejected_transactions
ORDER BY rejected_at DESC
LIMIT 5;
