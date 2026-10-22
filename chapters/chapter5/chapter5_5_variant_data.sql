-- =============================================================================
-- Chapter 5 — Section 5: Transforming Semi-Structured VARIANT Data.
-- Standalone: run chapter5_0_setup.sql once first, then this file top to
-- bottom. Landing tables and sample payloads are embedded here.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;


-- =============================================================================
-- Landing tables + sample data
-- =============================================================================

CREATE TABLE IF NOT EXISTS raw_db.streaming.raw_transactions (
    raw_data    VARIANT,
    _loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS raw_db.streaming.raw_orders (
    raw_data    VARIANT,
    _loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS raw_db.streaming.raw_fhir_patients (
    payload     STRING,
    _loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS raw_db.streaming.raw_fhir_claims (
    payload     STRING,
    _loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- JSON transactions. TXN-1002 intentionally carries "amount": "N/A" — a dirty
-- record that motivates the TRY_CAST defense in 5.3.
TRUNCATE TABLE raw_db.streaming.raw_transactions;

INSERT INTO raw_db.streaming.raw_transactions (raw_data)
SELECT PARSE_JSON(col) FROM VALUES
    ('{
        "transaction_id": "TXN-1001",
        "customer": {"id": "C1001", "name": "Alice Smith"},
        "amount": 149.99,
        "timestamp": "2025-10-01T12:30:00",
        "metadata": {"channel": "MOBILE", "risk_score": 5.25},
        "line_items": [
            {"product_id": "SKU-A", "quantity": 2, "unit_price": 49.99},
            {"product_id": "SKU-B", "quantity": 1, "unit_price": 50.01}
        ]
    }'),
    ('{
        "transaction_id": "TXN-1002",
        "customer": {"id": "C1002", "name": "Bob Jones"},
        "amount": "N/A",
        "timestamp": "2025-10-01T12:31:15",
        "metadata": {"channel": "WEB"},
        "line_items": [
            {"product_id": "SKU-C", "quantity": 3, "unit_price": 10.00}
        ]
    }'),
    ('{
        "transaction_id": "TXN-1003",
        "customer": {"id": "C1003", "name": "Carol White"},
        "amount": 89.50,
        "timestamp": "2025-10-01T12:35:40",
        "metadata": {"channel": "API", "risk_score": 2.00}
    }')
AS t(col);

-- Nested arrays for chained FLATTEN (orders > shipments > items).
TRUNCATE TABLE raw_db.streaming.raw_orders;

INSERT INTO raw_db.streaming.raw_orders (raw_data)
SELECT PARSE_JSON(col) FROM VALUES
    ('{
        "order_id": "ORD-5001",
        "shipments": [
            {
                "shipment_id": "SHP-1",
                "items": [
                    {"sku": "SKU-A", "quantity": 2},
                    {"sku": "SKU-B", "quantity": 1}
                ]
            },
            {
                "shipment_id": "SHP-2",
                "items": [
                    {"sku": "SKU-C", "quantity": 5}
                ]
            }
        ]
    }'),
    ('{
        "order_id": "ORD-5002",
        "shipments": [
            {
                "shipment_id": "SHP-3",
                "items": [
                    {"sku": "SKU-D", "quantity": 10},
                    {"sku": "SKU-E", "quantity": 4},
                    {"sku": "SKU-F", "quantity": 1}
                ]
            }
        ]
    }')
AS t(col);

-- FHIR-style XML payloads for the 5.4 PARSE_XML / XMLGET examples.
-- Stored as STRING (PARSE_XML is applied on read in the chapter queries).
TRUNCATE TABLE raw_db.streaming.raw_fhir_patients;
TRUNCATE TABLE raw_db.streaming.raw_fhir_claims;

INSERT INTO raw_db.streaming.raw_fhir_patients (payload)
VALUES
    ('<Patient><id value="P-1024"/><gender value="female"/><birthDate value="1982-03-14"/><address><city value="Boston"/><state value="MA"/></address></Patient>'),
    ('<Patient><id value="P-1025"/><gender value="male"/><birthDate value="1975-11-02"/><address><city value="Cambridge"/><state value="MA"/></address></Patient>'),
    ('<Patient><id value="P-1026"/><gender value="female"/><birthDate value="1990-07-21"/><address><city value="Providence"/><state value="RI"/></address></Patient>');

INSERT INTO raw_db.streaming.raw_fhir_claims (payload)
VALUES
    ('<Claim><id value="CLM-2001"/><patient value="P-1024"/><diagnosis><sequence value="1"/><code value="I25.10"/></diagnosis><diagnosis><sequence value="2"/><code value="I25.9"/></diagnosis></Claim>'),
    ('<Claim><id value="CLM-2002"/><patient value="P-1025"/><diagnosis><sequence value="1"/><code value="I25.10"/></diagnosis></Claim>');


-- =============================================================================
-- 5.1 Extracting and Casting VARIANT Fields
-- =============================================================================

-- Chapter listing (copy-paste from the book). Against the dirty TXN-1002 seed
-- ("amount": "N/A") the direct ::NUMBER cast RAISES — that error motivates 5.3.
/*
SELECT
    raw_data:transaction_id::STRING         AS transaction_id,
    raw_data:customer.id::STRING            AS customer_id,
    raw_data:customer.name::STRING          AS customer_name,
    raw_data:amount::NUMBER(12,2)           AS amount,
    raw_data:timestamp::TIMESTAMP_NTZ       AS transaction_ts,
    raw_data:metadata.channel::STRING       AS channel,
    raw_data:metadata.risk_score::NUMBER(5,2) AS risk_score
FROM raw_db.streaming.raw_transactions;
*/

-- Runnable variant (skips non-numeric amounts).
SELECT
    raw_data:transaction_id::STRING           AS transaction_id,
    raw_data:customer.id::STRING              AS customer_id,
    raw_data:customer.name::STRING            AS customer_name,
    raw_data:amount::NUMBER(12,2)             AS amount,
    raw_data:timestamp::TIMESTAMP_NTZ         AS transaction_ts,
    raw_data:metadata.channel::STRING         AS channel,
    raw_data:metadata.risk_score::NUMBER(5,2) AS risk_score
FROM raw_db.streaming.raw_transactions
WHERE TRY_CAST(raw_data:amount::STRING AS NUMBER(12,2)) IS NOT NULL
   OR raw_data:amount IS NULL;


-- =============================================================================
-- 5.2 Flattening Arrays with LATERAL FLATTEN
-- =============================================================================

-- Expected on the seed: 3 rows (line_items).
SELECT
    t.raw_data:transaction_id::STRING        AS transaction_id,
    t.raw_data:timestamp::TIMESTAMP_NTZ      AS transaction_ts,
    li.value:product_id::STRING              AS product_id,
    li.value:quantity::INT                   AS quantity,
    li.value:unit_price::NUMBER(10,2)        AS unit_price,
    li.value:quantity::INT * li.value:unit_price::NUMBER(10,2) AS line_total
FROM raw_db.streaming.raw_transactions t,
    LATERAL FLATTEN(input => t.raw_data:line_items) li
WHERE t.raw_data:line_items IS NOT NULL;

-- Chained FLATTEN for deeply nested arrays. Expected on the seed: 6 rows.
SELECT
    t.raw_data:order_id::STRING   AS order_id,
    s.value:shipment_id::STRING   AS shipment_id,
    item.value:sku::STRING        AS sku,
    item.value:quantity::INT      AS quantity
FROM raw_db.streaming.raw_orders t,
    LATERAL FLATTEN(input => t.raw_data:shipments) s,
    LATERAL FLATTEN(input => s.value:items) item;


-- =============================================================================
-- 5.3 Handling Type-Casting Edge Cases
-- =============================================================================
--
-- TRY_CAST accepts only string expressions. Calling it directly on a VARIANT
-- extraction fails with:
--     "Function TRY_CAST cannot be used with arguments of types VARIANT and NUMBER(12,2)".
-- Extract to STRING first, then TRY_CAST, as the chapter and the query below do.
-- Equivalent alternative: TRY_TO_NUMBER(raw_data:amount::STRING, 12, 2).

SELECT
    raw_data:transaction_id::STRING                        AS transaction_id,
    TRY_CAST(raw_data:amount::STRING AS NUMBER(12,2))      AS amount,
    CASE
        WHEN TRY_CAST(raw_data:amount::STRING AS NUMBER(12,2)) IS NULL
             AND raw_data:amount IS NOT NULL
        THEN 'PARSE_ERROR'
        WHEN raw_data:amount IS NULL THEN 'MISSING'
        ELSE 'OK'
    END                                                    AS amount_status
FROM raw_db.streaming.raw_transactions;

-- Exploration helpers mentioned in 5.3
SELECT OBJECT_KEYS(raw_data) AS top_level_keys,
       TYPEOF(raw_data:amount) AS amount_type
FROM raw_db.streaming.raw_transactions
LIMIT 10;


-- =============================================================================
-- 5.4 Parsing XML with PARSE_XML and XMLGET
-- =============================================================================

-- Inline XML literal: parse a simplified FHIR Patient resource into VARIANT.
SELECT
    PARSE_XML('
      <Patient>
        <id value="P-1024"/>
        <gender value="female"/>
        <birthDate value="1982-03-14"/>
        <address>
          <city value="Boston"/>
          <state value="MA"/>
        </address>
      </Patient>
    ') AS patient_xml;

-- XMLGET-based extraction with chained calls.
-- GET(element, '@attribute') extracts an attribute value.
-- GET(element, '$') extracts text content between the tags.
WITH parsed AS (
    SELECT PARSE_XML(payload) AS patient_xml
    FROM raw_db.streaming.raw_fhir_patients
)
SELECT
    GET(XMLGET(patient_xml, 'id'),         '@value')::STRING AS patient_id,
    GET(XMLGET(patient_xml, 'gender'),     '@value')::STRING AS gender,
    GET(XMLGET(patient_xml, 'birthDate'),  '@value')::DATE   AS birth_date,
    GET(XMLGET(XMLGET(patient_xml, 'address'), 'city'),  '@value')::STRING AS city,
    GET(XMLGET(XMLGET(patient_xml, 'address'), 'state'), '@value')::STRING AS state
FROM parsed;

-- Repeated elements: pair XMLGET with LATERAL FLATTEN over the root's child
-- array. Each child element exposes a "@" key (tag name) and a "$" key
-- (content) — Snowflake's convention for representing XML as VARIANT.
WITH parsed AS (
    SELECT PARSE_XML(payload) AS claim_xml
    FROM raw_db.streaming.raw_fhir_claims
)
SELECT
    GET(XMLGET(claim_xml, 'id'), '@value')::STRING          AS claim_id,
    GET(XMLGET(diag.value, 'sequence'), '@value')::INT      AS diag_sequence,
    GET(XMLGET(diag.value, 'code'),     '@value')::STRING   AS diag_code
FROM parsed,
    LATERAL FLATTEN(input => claim_xml:"$") diag
WHERE diag.value:"@" = 'diagnosis';
