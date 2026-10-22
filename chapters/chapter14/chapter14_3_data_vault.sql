-- =============================================================================
-- Chapter 14: Data Modeling in Snowflake using AI-Assisted Practices
-- Section 4: Introducing Data Vault for complex enterprises (OPTIONAL)
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 4.1 Understanding hubs, links, and satellites. The chapter shows the
-- hub and satellite DDL, describes the link, and points here for the rest; this file is the complete, runnable
-- vault the chapter points to: two simulated source extracts, hubs, a link,
-- two satellites, idempotent loaders that read the extracts, a point-in-time
-- (PIT) table, and a dimensional mart on top. Runs standalone once
-- chapter14_0_setup.sql has run.
--
-- OPTIONAL: The lab requirements can be met by the existing dimensional
-- layer. This file illustrates vault mechanics without making source count
-- an adoption threshold. Everything lands in the chapter-owned vault_db.
--
-- Prerequisites: chapter14_0_setup.sql. CREATE DATABASE privilege (SYSADMIN
-- has it). Section 3 is NOT required, but if you ran it the satellite carries
-- the movers' two versions, which makes the PIT table more interesting.
--
-- Role convention: SYSADMIN.
-- Placeholder convention: <REPLACE: ...>. This file has none.
--
-- Reversibility: teardown drops vault_db and the two source extracts under
-- raw_db (raw_db.crm.customer_history, raw_db.partners.merchant_directory).
-- Nothing else outside vault_db is touched.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;

CREATE DATABASE IF NOT EXISTS vault_db
    COMMENT = 'Chapter 14 Data Vault example (chapter-owned, drop freely)';
CREATE SCHEMA IF NOT EXISTS vault_db.rawvault
    COMMENT = 'Raw vault: hubs, links, satellites loaded as-is from sources';
CREATE SCHEMA IF NOT EXISTS vault_db.marts
    COMMENT = 'Dimensional marts and PIT tables presented to consumers';

USE DATABASE vault_db;
USE SCHEMA rawvault;


-- =============================================================================
-- 0a. The source extracts the vault loads from
-- -----------------------------------------------------------------------------
-- A raw vault loads from source systems, and the marts sit above it. The
-- account has no CRM or partner system to extract from, so this block stages
-- the two source extracts from the data already in the account: every
-- customer version as the CRM would export it (the CRM keeps its own history,
-- so the extract carries effective_from), and the partner directory as its
-- current state. The loaders below read only these two tables and the payment
-- events; they never read the dimensional mart as a source. Rebuilt on every
-- run so a section 3 change upstream reaches the vault.
-- =============================================================================

CREATE OR REPLACE TABLE raw_db.crm.customer_history
    COMMENT = 'Chapter 14 simulated CRM export: every customer version, source-effective from effective_from'
AS
SELECT customer_id, customer_name, email, address_line1, city, state,
       postal_code, effective_from
  FROM gold_db.customers.dim_customers;

CREATE OR REPLACE TABLE raw_db.partners.merchant_directory
    COMMENT = 'Chapter 14 simulated partner directory export: current merchant attributes'
AS
SELECT merchant_id, merchant_name, merchant_category, merchant_city
  FROM gold_db.merchants.dim_merchants;

-- Expected: 'Table CUSTOMER_HISTORY successfully created.' and
-- 'Table MERCHANT_DIRECTORY successfully created.' on every run.


-- =============================================================================
-- 0b. One hash recipe, in one place
-- -----------------------------------------------------------------------------
-- All fixture loaders use the same trim/upper-case hash recipe. Each hub
-- has one identifier domain and its identifiers are case-insensitive.
-- Before combining independent source domains, establish shared identity or
-- include an agreed domain discriminator. Equal text does not prove identity.
-- Hashing removes sequence allocation, not the need to prevent duplicates
-- across concurrent loaders. Changing the recipe requires a migration.
-- =============================================================================

CREATE OR REPLACE FUNCTION vault_db.rawvault.hk(business_key VARCHAR)
RETURNS BINARY
COMMENT = 'Hash key recipe: SHA-256 of the trimmed, upper-cased business key'
AS
$$
    SHA2_BINARY(UPPER(TRIM(business_key)), 256)
$$;

-- Expected: 'Function HK successfully created.'


-- =============================================================================
-- 1. Hubs and satellites: identity apart from description
-- -----------------------------------------------------------------------------
-- The customer hub and its CRM satellite appear first, in the order the chapter
-- shows them; the merchant pair follows.
-- =============================================================================

CREATE TABLE IF NOT EXISTS vault_db.rawvault.hub_customer (
    customer_hk   BINARY(32)    NOT NULL,
    customer_id   VARCHAR       NOT NULL,
    load_ts       TIMESTAMP_NTZ NOT NULL,
    record_source VARCHAR       NOT NULL
);


CREATE TABLE IF NOT EXISTS vault_db.rawvault.sat_customer_crm (
    customer_hk   BINARY(32)    NOT NULL,
    load_ts       TIMESTAMP_NTZ NOT NULL,
    record_source VARCHAR       NOT NULL,
    hash_diff     BINARY(32)    NOT NULL,
    customer_name VARCHAR,
    email         VARCHAR,
    city          VARCHAR,
    state         VARCHAR
);

CREATE TABLE IF NOT EXISTS vault_db.rawvault.hub_merchant (
    merchant_hk   BINARY(32)    NOT NULL,
    merchant_id   VARCHAR       NOT NULL,
    load_ts       TIMESTAMP_NTZ NOT NULL,
    record_source VARCHAR       NOT NULL
);

CREATE TABLE IF NOT EXISTS vault_db.rawvault.sat_merchant_partner (
    merchant_hk       BINARY(32)    NOT NULL,
    load_ts           TIMESTAMP_NTZ NOT NULL,
    record_source     VARCHAR       NOT NULL,
    hash_diff         BINARY(32)    NOT NULL,
    merchant_name     VARCHAR,
    merchant_category VARCHAR,
    merchant_city     VARCHAR
);


-- =============================================================================
-- 2. Link: the relationship between hubs, one row per distinct association.
--    Keyed by transaction_id, link_payment is what Data Vault 2.0 calls a
--    non-historized (transactional) link: one immutable row per event.
-- =============================================================================

CREATE TABLE IF NOT EXISTS vault_db.rawvault.link_payment (
    payment_hk     BINARY(32)    NOT NULL,
    customer_hk    BINARY(32)    NOT NULL,
    merchant_hk    BINARY(32)    NOT NULL,
    transaction_id VARCHAR       NOT NULL,
    load_ts        TIMESTAMP_NTZ NOT NULL,
    record_source  VARCHAR       NOT NULL
);

-- Expected so far: five tables created (or 'already exists' on a re-run).


-- =============================================================================
-- 3. Loaders: insert-only and idempotent. They read the two source extracts
--    staged in block 0a and the payment events; the marts in block 5 sit
--    above the vault, never beside it as a source.
-- -----------------------------------------------------------------------------
-- Hubs and links use MERGE with only a WHEN NOT MATCHED branch: a key seen
-- before is left unchanged, a new one is inserted. The customer satellite
-- loads unseen source-version timestamps; the merchant satellite compares
-- incoming attributes with its latest stored hash. Both assume previously
-- loaded source versions are immutable. These loaders insert only and reruns
-- on unchanged sources add no rows.
-- =============================================================================

-- 3a. Hub loaders. Customers come from every version in the CRM export
-- (identity is identity, however many versions exist); merchants from the
-- partner directory. The source is grouped by the NORMALIZED key, not the
-- raw spelling: hk() hashes UPPER(TRIM(key)), so 'C-1001' and 'c-1001 ' hash
-- the same and must reach the MERGE as one row, or the WHEN NOT MATCHED branch
-- tries to insert the same hub key twice in one statement. The hub stores the
-- normalized spelling beside the hash, so every consumer of the hub sees one
-- form of the key. The validation set at the end applies the same rule.
MERGE INTO vault_db.rawvault.hub_customer tgt
USING (
    SELECT vault_db.rawvault.hk(customer_id) AS customer_hk,
           UPPER(TRIM(customer_id))          AS customer_id
      FROM raw_db.crm.customer_history
     GROUP BY 1, 2
) src
   ON tgt.customer_hk = src.customer_hk
WHEN NOT MATCHED THEN
    INSERT (customer_hk, customer_id, load_ts, record_source)
    VALUES (src.customer_hk, src.customer_id, CURRENT_TIMESTAMP(),
            'raw_db.crm.customer_history');

-- Expected: number of rows inserted = distinct customers (roughly 510 with the
-- stock fixture: 500 seeded, the Chapter 5 customers, and the section 3 signup).

MERGE INTO vault_db.rawvault.hub_merchant tgt
USING (
    SELECT vault_db.rawvault.hk(merchant_id) AS merchant_hk,
           UPPER(TRIM(merchant_id))          AS merchant_id
      FROM raw_db.partners.merchant_directory
     GROUP BY 1, 2
) src
   ON tgt.merchant_hk = src.merchant_hk
WHEN NOT MATCHED THEN
    INSERT (merchant_hk, merchant_id, load_ts, record_source)
    VALUES (src.merchant_hk, src.merchant_id, CURRENT_TIMESTAMP(),
            'raw_db.partners.merchant_directory');

-- Expected: one row per merchant (47, or 48 after section 3).

-- 3b. Satellite loaders. Two source shapes, two dedupe rules.
--
-- The CRM export carries history (every customer version, stamped with its
-- effective_from), so each version becomes a satellite row keyed by that
-- timestamp, and the loader skips any (hub key, load_ts) it already holds.
-- Comparing against the latest stored hash instead would re-insert older
-- versions on a re-run when their hashes differ from the newest version.
--
-- The customer satellite uses load_ts for source-effective time as a lab
-- simplification. A full audit model keeps business-effective time and load
-- arrival time in separate columns; this example cannot reconstruct what the
-- warehouse knew before arrival. The fixture assumes source effective_from
-- reflects the business change. The merchant satellite and hubs use
-- CURRENT_TIMESTAMP() for arrival time. Do not treat these meanings as
-- interchangeable when extending the model.
INSERT INTO vault_db.rawvault.sat_customer_crm
    (customer_hk, load_ts, record_source, hash_diff,
     customer_name, email, city, state)
WITH incoming AS (
    SELECT vault_db.rawvault.hk(customer_id) AS customer_hk,
           effective_from                    AS load_ts,
           SHA2_BINARY(CONCAT_WS('|', NVL(customer_name, ''), NVL(email, ''),
                                 NVL(city, ''), NVL(state, '')), 256)
                                             AS hash_diff,
           customer_name, email, city, state
      FROM raw_db.crm.customer_history
)
SELECT i.customer_hk, i.load_ts, 'raw_db.crm.customer_history',
       i.hash_diff, i.customer_name, i.email, i.city, i.state
  FROM incoming i
 WHERE NOT EXISTS (
        SELECT 1
          FROM vault_db.rawvault.sat_customer_crm s
         WHERE s.customer_hk = i.customer_hk
           AND s.load_ts     = i.load_ts)
QUALIFY ROW_NUMBER() OVER (PARTITION BY i.customer_hk, i.load_ts
                           ORDER BY i.hash_diff) = 1;

-- Expected: one row per customer version on the first run (a few more than the
-- hub count after section 3: the two movers carry two versions each). Re-run:
-- zero rows.

-- The partner directory is current-state only (no history column), so the rule
-- is the classic one: insert when the incoming hash differs from the latest
-- stored hash for that hub key. A re-run on an unchanged source inserts
-- nothing; a Type 1 correction upstream inserts one new row and keeps the old.

INSERT INTO vault_db.rawvault.sat_merchant_partner
    (merchant_hk, load_ts, record_source, hash_diff,
     merchant_name, merchant_category, merchant_city)
WITH incoming AS (
    SELECT vault_db.rawvault.hk(merchant_id) AS merchant_hk,
           SHA2_BINARY(CONCAT_WS('|', NVL(merchant_name, ''),
                                 NVL(merchant_category, ''),
                                 NVL(merchant_city, '')), 256) AS hash_diff,
           merchant_name, merchant_category, merchant_city
      FROM raw_db.partners.merchant_directory
),
latest AS (
    SELECT merchant_hk, hash_diff
      FROM vault_db.rawvault.sat_merchant_partner
     QUALIFY ROW_NUMBER() OVER (PARTITION BY merchant_hk
                                ORDER BY load_ts DESC) = 1
)
SELECT i.merchant_hk, CURRENT_TIMESTAMP(), 'raw_db.partners.merchant_directory',
       i.hash_diff, i.merchant_name, i.merchant_category, i.merchant_city
  FROM incoming i
  LEFT JOIN latest l
    ON l.merchant_hk = i.merchant_hk
 WHERE l.merchant_hk IS NULL
    OR l.hash_diff <> i.hash_diff;

-- Expected: one row per merchant on the first run. Re-run after a Type 1
-- correction in section 3 and only the corrected merchants gain a row. The
-- satellite can preserve the prior value only if it loaded that value before
-- the overwrite; it cannot recover versions the source already discarded.

-- 3c. Link loader: one row per payment, carrying the degenerate transaction_id.
-- Payment events have no separate raw table in the account (Chapter 5's raw
-- layer is rebuilt per run), so the fact table is the payment feed here.
MERGE INTO vault_db.rawvault.link_payment tgt
USING (
    SELECT vault_db.rawvault.hk(transaction_id) AS payment_hk,
           vault_db.rawvault.hk(customer_id)    AS customer_hk,
           vault_db.rawvault.hk(merchant_id)    AS merchant_hk,
           transaction_id
      FROM gold_db.transactions.fact_transactions
) src
   ON tgt.payment_hk = src.payment_hk
WHEN NOT MATCHED THEN
    INSERT (payment_hk, customer_hk, merchant_hk, transaction_id,
            load_ts, record_source)
    VALUES (src.payment_hk, src.customer_hk, src.merchant_hk,
            src.transaction_id, CURRENT_TIMESTAMP(),
            'gold_db.transactions.fact_transactions');

-- Expected: number of rows inserted = fact row count (50,024 with the stock
-- fixture). Re-run any loader in this block: zero rows.


-- =============================================================================
-- 4. A point-in-time (PIT) table
-- -----------------------------------------------------------------------------
-- For each month start in the seeded window and each customer, the satellite
-- source-effective version for that date, stored here in satellite load_ts.
-- This is an effective-time lookup, not an arrival-time audit. Marts join to
-- the PIT table instead of deriving validity windows on every query.
-- =============================================================================

CREATE OR REPLACE TABLE vault_db.marts.pit_customer AS
WITH as_of AS (
    SELECT DATEADD('month', seq, '2025-01-01'::DATE)::TIMESTAMP_NTZ AS as_of_ts
      FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1 AS seq
              FROM TABLE(GENERATOR(ROWCOUNT => 19)))
)
SELECT a.as_of_ts,
       h.customer_hk,
       s.load_ts AS sat_customer_crm_load_ts
  FROM as_of a
 CROSS JOIN vault_db.rawvault.hub_customer h
  JOIN vault_db.rawvault.sat_customer_crm s
    ON s.customer_hk = h.customer_hk
   AND s.load_ts    <= a.as_of_ts
QUALIFY ROW_NUMBER() OVER (PARTITION BY a.as_of_ts, h.customer_hk
                           ORDER BY s.load_ts DESC) = 1;

-- Expected: 19 month-starts (2025-01 through 2026-07) times the customers
-- known on each date. After section 3, the movers point at their first version
-- through 2026-03-01 and at the Florida version from 2026-04-01 onward.


-- =============================================================================
-- 5. The dimensional mart presents customer attributes for reporting
-- -----------------------------------------------------------------------------
-- A current-state customer dimension rebuilt from hub plus latest satellite
-- row. Consumers see the star they already know; the vault sits beneath it.
-- =============================================================================

CREATE OR REPLACE VIEW vault_db.marts.dim_customers_vault AS
SELECT h.customer_id,
       s.customer_name, s.email, s.city, s.state,
       s.load_ts AS attributes_as_of
  FROM vault_db.rawvault.hub_customer h
  JOIN vault_db.rawvault.sat_customer_crm s
    ON s.customer_hk = h.customer_hk
 QUALIFY ROW_NUMBER() OVER (PARTITION BY h.customer_hk
                            ORDER BY s.load_ts DESC) = 1;

-- Expected: one row per customer, matching gold_db.customers.dim_customers_current
-- on the tracked attributes.


-- =============================================================================
-- Section 4 validation set
-- =============================================================================

-- The counts compare on the loader's own key definition, UPPER(TRIM(id)):
-- a source that spells one customer two ways still has one hub row, and the
-- validation must agree with the loader, not with the raw spelling.
SELECT 'hub_customer_matches_distinct_customers' AS check_name,
       (SELECT COUNT(*) FROM vault_db.rawvault.hub_customer)
       = (SELECT COUNT(DISTINCT UPPER(TRIM(customer_id)))
            FROM raw_db.crm.customer_history)                  AS passed
UNION ALL
SELECT 'link_matches_fact_rows',
       (SELECT COUNT(*) FROM vault_db.rawvault.link_payment)
       = (SELECT COUNT(*) FROM gold_db.transactions.fact_transactions)
UNION ALL
SELECT 'mart_matches_current_slice',
       (SELECT COUNT(*) FROM vault_db.marts.dim_customers_vault v
          JOIN gold_db.customers.dim_customers_current c
            ON UPPER(TRIM(c.customer_id)) = v.customer_id
           AND NVL(c.state, '') = NVL(v.state, ''))
       = (SELECT COUNT(*) FROM gold_db.customers.dim_customers_current)
UNION ALL
SELECT 'no_duplicate_hub_keys',
       (SELECT COUNT(*) - COUNT(DISTINCT customer_hk)
          FROM vault_db.rawvault.hub_customer) = 0;

-- Expected: four rows, every passed = TRUE (the mart check compares the vault's
-- current slice with the gold dimension's, which the same extract fed). Run
-- chapter14_4_coco.sql next, or chapter14_teardown.sql to remove vault_db and
-- the two extracts.
