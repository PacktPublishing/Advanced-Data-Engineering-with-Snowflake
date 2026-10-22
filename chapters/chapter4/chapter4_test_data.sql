-- =============================================================================
-- Chapter 4: Test Data for CDC Exercises
-- Run AFTER chapter4_cdc_setup.sql has been deployed.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;

-- =============================================================================
-- 1. Customer records for Streams + MERGE CDC (Sections 5.1-5.2)
-- =============================================================================

INSERT INTO RAW_DB.LANDING.customers
    (customer_id, name, email, status, created_at, updated_at)
VALUES
    ('C001', 'Alice Smith',   'alice@example.com',  'ACTIVE', '2025-01-15'::TIMESTAMP_NTZ, '2025-01-15'::TIMESTAMP_NTZ),
    ('C002', 'Bob Jones',     'bob@example.com',    'ACTIVE', '2025-02-20'::TIMESTAMP_NTZ, '2025-02-20'::TIMESTAMP_NTZ),
    ('C003', 'Carol White',   'carol@example.com',  'ACTIVE', '2025-03-10'::TIMESTAMP_NTZ, '2025-03-10'::TIMESTAMP_NTZ),
    ('C004', 'Dave Brown',    'dave@example.com',   'ACTIVE', '2025-06-01'::TIMESTAMP_NTZ, '2025-06-01'::TIMESTAMP_NTZ),
    ('C005', 'Eve Green',     'eve@example.com',    'ACTIVE', '2025-09-15'::TIMESTAMP_NTZ, '2025-09-15'::TIMESTAMP_NTZ);

-- Verify stream captured the initial inserts
SELECT METADATA$ACTION, METADATA$ISUPDATE, customer_id, name, email
FROM RAW_DB.CDC.customer_changes;

-- Simulate an UPDATE (triggers INSERT+DELETE pair in stream with METADATA$ISUPDATE=TRUE)
UPDATE RAW_DB.LANDING.customers
SET email = 'alice.new@example.com', updated_at = CURRENT_TIMESTAMP()
WHERE customer_id = 'C001';

-- Simulate a DELETE (triggers DELETE in stream with METADATA$ISUPDATE=FALSE)
DELETE FROM RAW_DB.LANDING.customers WHERE customer_id = 'C003';

-- Simulate a new INSERT after initial load
INSERT INTO RAW_DB.LANDING.customers
    (customer_id, name, email, status, created_at, updated_at)
VALUES
    ('C006', 'Frank Black', 'frank@example.com', 'ACTIVE', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

-- Check stream now shows all change types
SELECT METADATA$ACTION, METADATA$ISUPDATE, customer_id, name, email
FROM RAW_DB.CDC.customer_changes
ORDER BY customer_id;


-- =============================================================================
-- 2. VARIANT records for Schema Evolution (Section 5.4)
-- =============================================================================

-- Records WITHOUT the phone field (original schema)
-- Single-line JSON: Snowflake rejects multiline string literals inside PARSE_JSON in VALUES (002014).
INSERT INTO RAW_DB.LANDING.customers_raw (source_id, payload, _cdc_operation, _source_timestamp)
VALUES
    ('src-001', PARSE_JSON('{"customer_id":"C010","name":"Grace Hopper","email":"grace@example.com","status":"ACTIVE","created_at":"2026-01-01T00:00:00","updated_at":"2026-01-01T00:00:00"}'), 'INSERT', CURRENT_TIMESTAMP()),
    ('src-002', PARSE_JSON('{"customer_id":"C011","name":"Alan Turing","email":"alan@example.com","status":"ACTIVE","created_at":"2026-01-15T00:00:00","updated_at":"2026-01-15T00:00:00"}'), 'INSERT', CURRENT_TIMESTAMP());

-- Records WITH the phone field (evolved schema)
INSERT INTO RAW_DB.LANDING.customers_raw (source_id, payload, _cdc_operation, _source_timestamp)
VALUES
    ('src-003', PARSE_JSON('{"customer_id":"C012","name":"Ada Lovelace","email":"ada@example.com","status":"ACTIVE","phone":"+1-555-0100","created_at":"2026-02-01T00:00:00","updated_at":"2026-02-01T00:00:00"}'), 'INSERT', CURRENT_TIMESTAMP()),
    ('src-004', PARSE_JSON('{"customer_id":"C010","name":"Grace Hopper","email":"grace.new@example.com","status":"ACTIVE","phone":"+1-555-0200","created_at":"2026-01-01T00:00:00","updated_at":"2026-03-15T00:00:00"}'), 'UPDATE', CURRENT_TIMESTAMP());

-- Verify the typed view handles both schemas gracefully
SELECT customer_id, name, email, phone, _cdc_operation
FROM RAW_DB.LANDING.customers_typed
ORDER BY customer_id, _source_timestamp;
