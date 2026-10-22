-- =============================================================================
-- Chapter 5 — Section 3: Building Incremental Transformation Patterns.
-- Standalone: run chapter5_0_setup.sql once first, then this file top to
-- bottom. Sample data is embedded below each DDL block. For the SCD Type 2
-- two-row effect, follow the staged observation flow at the end of 3.1.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;


-- =============================================================================
-- 3.1 Implementing SCD Type 2 with Streams and a Stable-Delta Transaction
-- =============================================================================

-- Target dimension. customer_key is the surrogate key (medallion convention
-- uses _key suffix for primary keys); auto-increment for clarity here, though
-- a deterministic SHA2(CONCAT_WS('|', customer_id, effective_from)) is also
-- valid when reproducibility on rebuild matters. effective_from/effective_to
-- stay TIMESTAMP_NTZ: the pipeline stores every timestamp in UTC (same
-- convention as the Chapter 4 ingestion tables).
CREATE OR REPLACE TABLE gold_db.customers.dim_customers (
    customer_key    NUMBER AUTOINCREMENT,
    customer_id     STRING        NOT NULL,
    customer_name   STRING,
    email           STRING,
    address_line1   STRING,
    city            STRING,
    state           STRING,
    postal_code     STRING,
    effective_from  TIMESTAMP_NTZ NOT NULL,
    effective_to    TIMESTAMP_NTZ DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    is_current      BOOLEAN       DEFAULT TRUE,
    record_hash     STRING        NOT NULL,
    CONSTRAINT pk_dim_customers PRIMARY KEY (customer_key)
);

-- Bronze source + stream for the SCD Type 2 example.
CREATE TABLE IF NOT EXISTS raw_db.crm.customer (
    customer_id     STRING NOT NULL,
    customer_name   STRING,
    email           STRING,
    address_line1   STRING,
    city            STRING,
    state           STRING,
    postal_code     STRING,
    updated_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE STREAM IF NOT EXISTS raw_db.crm.customer_stream
    ON TABLE raw_db.crm.customer
    APPEND_ONLY = FALSE
    SHOW_INITIAL_ROWS = TRUE;

-- Verify table
DESCRIBE TABLE gold_db.customers.dim_customers;

-- Sample data: initial CRM inserts (captured by the stream as
-- METADATA$ACTION='INSERT').
TRUNCATE TABLE raw_db.crm.customer;

INSERT INTO raw_db.crm.customer
    (customer_id, customer_name, email, address_line1, city, state, postal_code, updated_at)
VALUES
    ('C1001', 'Alice Smith',   'alice@example.com',   '100 Main St',  'Toronto',  'ON', 'M5V 2T6', CURRENT_TIMESTAMP()),
    ('C1002', 'Bob Jones',     'bob@example.com',     '22 King St',   'Montreal', 'QC', 'H3A 1A1', CURRENT_TIMESTAMP()),
    ('C1003', 'Carol White',   'carol@example.com',   '7 Queen Ave',  'Calgary',  'AB', 'T2P 0B1', CURRENT_TIMESTAMP());

-- Stable-delta transaction (chapter pattern): read the stream once into a temp
-- delta, classify NEW/CHANGED/UNCHANGED, close prior versions, then INSERT.
-- Avoids MERGE limitations on the same matched row for SCD Type 2.
-- NVL wrapping inside CONCAT_WS matters: without it, NULL hash drift.
BEGIN;

CREATE OR REPLACE TEMP TABLE customer_delta AS
SELECT
    src.customer_id,
    src.customer_name,
    src.email,
    src.address_line1,
    src.city,
    src.state,
    src.postal_code,
    src.record_hash,
    src.load_ts,
    CASE
        WHEN tgt.customer_id IS NULL THEN 'NEW'
        WHEN tgt.record_hash <> src.record_hash THEN 'CHANGED'
        ELSE 'UNCHANGED'
    END AS change_type
FROM (
    SELECT
        customer_id,
        customer_name,
        email,
        address_line1,
        city,
        state,
        postal_code,
        SHA2(CONCAT_WS('|',
            NVL(customer_name, ''),
            NVL(email, ''),
            NVL(address_line1, ''),
            NVL(city, ''),
            NVL(state, ''),
            NVL(postal_code, '')
        )) AS record_hash,
        CURRENT_TIMESTAMP() AS load_ts
    FROM raw_db.crm.customer_stream
    WHERE METADATA$ACTION = 'INSERT'
) src
LEFT JOIN gold_db.customers.dim_customers tgt
    ON tgt.customer_id = src.customer_id
   AND tgt.is_current = TRUE;

UPDATE gold_db.customers.dim_customers tgt
SET
    effective_to = d.load_ts,
    is_current   = FALSE
FROM customer_delta d
WHERE tgt.customer_id = d.customer_id
  AND tgt.is_current  = TRUE
  AND d.change_type   = 'CHANGED';

INSERT INTO gold_db.customers.dim_customers (
    customer_id, customer_name, email, address_line1,
    city, state, postal_code,
    effective_from, record_hash
)
SELECT
    customer_id, customer_name, email, address_line1,
    city, state, postal_code,
    load_ts, record_hash
FROM customer_delta
WHERE change_type IN ('NEW', 'CHANGED');

COMMIT;

-- Verify: changed records should show two rows (closed + current)
SELECT customer_id, is_current, effective_from, effective_to
FROM gold_db.customers.dim_customers
ORDER BY customer_id, effective_from;

-- SCD Type 2 observation flow (run each step in a separate execution so the
-- stream offset advances between steps):
--
--   Step A: run the BEGIN ... COMMIT block above once.
--           -> inserts 3 rows in dim_customers, all is_current = TRUE.
--   Step B: run the UPDATE below.
--           UPDATE raw_db.crm.customer
--           SET email = 'alice.new@example.com', updated_at = CURRENT_TIMESTAMP()
--           WHERE customer_id = 'C1001';
--   Step C: run the BEGIN ... COMMIT block a second time.
--           -> closes the old C1001 row (is_current = FALSE, effective_to populated).
--   Step D: run the BEGIN ... COMMIT block a third time.
--           -> inserts the new C1001 version (is_current = TRUE).
--
-- Snowflake streams surface NET changes since the last consumption offset.
-- If Steps A, B, and C run before ever draining the stream, the INSERT+UPDATE
-- for C1001 collapses into a single INSERT row and the old-version close step
-- never fires. Draining in stages is what produces the Type 2 two-row effect.


-- =============================================================================
-- 3.2 Consolidating Dimensions with a Multi-Source MERGE
-- =============================================================================

-- Target EAV dimension. Avoids a MERGE trying to update 20 columns when only
-- one source changed. Materialize a wide table downstream when analysts need
-- the full profile in a single row.
CREATE OR REPLACE TABLE gold_db.customers.dim_customer_360 (
    customer_id     STRING        NOT NULL,
    attribute_name  STRING        NOT NULL,
    attribute_value STRING,
    last_updated    TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_dim_customer_360 PRIMARY KEY (customer_id, attribute_name)
);

-- Billing source + stream (CRM source already created in 3.1 above).
CREATE TABLE IF NOT EXISTS raw_db.billing.customer (
    customer_id    STRING NOT NULL,
    email          STRING,
    payment_method STRING,
    billing_city   STRING,
    updated_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE STREAM IF NOT EXISTS raw_db.billing.customer_stream
    ON TABLE raw_db.billing.customer
    APPEND_ONLY = FALSE
    SHOW_INITIAL_ROWS = TRUE;

-- Sample data: billing source rows.
TRUNCATE TABLE raw_db.billing.customer;

INSERT INTO raw_db.billing.customer
    (customer_id, email, payment_method, billing_city, updated_at)
VALUES
    ('C1001', 'alice.billing@example.com', 'VISA',  'Toronto',  CURRENT_TIMESTAMP()),
    ('C1002', 'bob@example.com',           'AMEX',  'Montreal', CURRENT_TIMESTAMP());

-- Multi-source MERGE: ROW_NUMBER() resolves source precedence per
-- (customer_id, attribute); CRM (priority 1) beats billing (priority 2),
-- most recent update wins within a priority.
MERGE INTO gold_db.customers.dim_customer_360 tgt
USING (
    WITH ranked_sources AS (
        SELECT *, ROW_NUMBER() OVER (
            PARTITION BY customer_id, attribute_name
            ORDER BY source_priority, updated_at DESC
        ) AS rn
        FROM (
            SELECT customer_id,
                   'email' AS attribute_name,
                   email   AS attribute_value,
                   1       AS source_priority,
                   updated_at
            FROM raw_db.crm.customer_stream
            WHERE METADATA$ACTION = 'INSERT'
            UNION ALL
            SELECT customer_id, 'email', email, 2, updated_at
            FROM raw_db.billing.customer_stream
            WHERE METADATA$ACTION = 'INSERT'
        )
    )
    SELECT * FROM ranked_sources WHERE rn = 1
) src
ON tgt.customer_id = src.customer_id
   AND tgt.attribute_name = src.attribute_name
WHEN MATCHED THEN UPDATE SET
    tgt.attribute_value = src.attribute_value,
    tgt.last_updated    = src.updated_at
WHEN NOT MATCHED THEN INSERT (customer_id, attribute_name, attribute_value, last_updated)
    VALUES (src.customer_id, src.attribute_name, src.attribute_value, src.updated_at);
