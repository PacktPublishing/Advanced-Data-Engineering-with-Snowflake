-- =============================================================================
-- Chapter 14: Data Modeling in Snowflake using AI-Assisted Practices
-- Section 3: Managing dimension history with SCD Types 1, 2, and 3
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 3.2 Applying Type 1 overwrites with MERGE, 3.3 Maintaining Type 2
-- history from batch extracts, 3.4 Querying history with point-in-time joins,
-- 3.5 Tracking alternate values with Type 3. Runs standalone top to bottom
-- once chapter14_0_setup.sql has run. Independent of chapter14_1.
--
-- Prerequisites: chapter14_0_setup.sql (fixtures in raw_db.partners and
-- raw_db.crm; Chapter 5 + 12 gold layer verified).
--
-- Role convention: SYSADMIN. Needs INSERT and UPDATE on
-- gold_db.merchants.dim_merchants and gold_db.customers.dim_customers, and
-- OWNERSHIP of dim_merchants for the Type 3 ALTER TABLE.
--
-- Placeholder convention: <REPLACE: ...>. This file has none.
--
-- THIS FILE WRITES INTO TWO TABLES EARLIER CHAPTERS OWN. Every write is
-- reversible: the merchants come back from the setup snapshot, the two closed
-- customer versions are reopened, and the inserted rows are identifiable by
-- fixed ids and a fixed effective_from. chapter14_teardown.sql does all of it.
--
-- Expected counts below assume the stock Chapter 5 + Chapter 12 fixtures and a
-- first run. A second run of any block reports zero rows changed (the Type 3
-- ALTER uses IF NOT EXISTS), which is the property the chapter asks you to
-- test. The Type 2 pair assumes one row per customer per extract, applied in
-- extract order; the guard inside the executable block enforces the first
-- half. The chapter's worksheet form of the pair is kept as a named comment
-- block in section 3.3 (see the convention note there).
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- =============================================================================
-- 3.2 Applying Type 1 overwrites with MERGE
-- -----------------------------------------------------------------------------
-- One statement, because Type 1 keeps nothing. IS DISTINCT FROM treats NULL as
-- a comparable value, so a correction that fills a NULL city still registers
-- as a change; a plain <> would compare to unknown and skip the row. The
-- guarded WHEN MATCHED clause makes the load idempotent.
-- =============================================================================

MERGE INTO gold_db.merchants.dim_merchants tgt
USING raw_db.partners.stg_merchant_updates src
   ON tgt.merchant_id = src.merchant_id
WHEN MATCHED AND
     (tgt.merchant_category IS DISTINCT FROM src.merchant_category
   OR tgt.merchant_city     IS DISTINCT FROM src.merchant_city) THEN
    UPDATE SET tgt.merchant_category = src.merchant_category,
               tgt.merchant_city     = src.merchant_city
WHEN NOT MATCHED THEN
    INSERT (merchant_id, merchant_name, merchant_category, merchant_city)
    VALUES (src.merchant_id, src.merchant_name,
            src.merchant_category, src.merchant_city);

-- Expected: number of rows inserted: 1, number of rows updated: 3.
-- Re-run the MERGE: both counts drop to zero.

-- Verify the overwrite landed.
SELECT m.merchant_id, m.merchant_name, m.merchant_category, m.merchant_city
  FROM gold_db.merchants.dim_merchants m
 WHERE m.merchant_id IN (SELECT merchant_id
                           FROM raw_db.partners.stg_merchant_updates)
 ORDER BY m.merchant_id;

-- Expected: four rows. Two carry Miami and Orlando, one carries its corrected
-- category, and MERCH-CH14-NEW01 is present with its name.

-- The Type 1 contract, visible: last quarter's revenue by category has moved
-- with the corrected merchant, and nothing flags it. Compare against the
-- Chapter 12 semantic view if you have it: the category totals differ from
-- what the view reported before this MERGE ran.


-- =============================================================================
-- 3.3 Maintaining Type 2 history from batch extracts
-- -----------------------------------------------------------------------------
-- This batch example requires staging to remain unchanged while the close
-- and insert run. Keep both statements in one transaction and roll back
-- together on failure. The hash recipe must match the stored dimension hash.
-- The fixture assumes extract_ts is the business-effective change time.
-- If extract_ts instead records extraction time, the windows describe when
-- changes were observed. Late or retroactive changes need a separate
-- effective timestamp and correction policy.
--
-- Batch contract: one row per customer per extract, extracts applied in order.
-- Two rows for one customer in a single extract would close the current
-- version twice (MERGE raises a nondeterministic-merge error) or insert two
-- current rows, so the executable block refuses a duplicate extract before the
-- transaction opens.
-- =============================================================================

-- Convention: the two statements the chapter shows are the WORKSHEET PAIR
-- BLOCK below, kept as a comment because this file must be safe under a
-- client that continues past errors (SnowSQL's default): a failed INSERT
-- followed by a bare COMMIT would keep the close and leave the movers with no
-- current row. The executable path is the Scripting block after it, which
-- carries the same two statements with the duplicate-extract guard before the
-- transaction and a ROLLBACK on any failure.
--
-- The worksheet pair block (run these two statements by hand in Snowsight, as
-- the chapter does; if the INSERT fails, run ROLLBACK before anything else,
-- since Snowflake rolls back only the failed statement and keeps the
-- transaction open, and any DDL would commit it):
--
-- BEGIN;
--
-- MERGE INTO gold_db.customers.dim_customers tgt
-- USING (
--     SELECT customer_id, extract_ts,
--            SHA2(CONCAT_WS('|', NVL(customer_name, ''),
--                 NVL(email, ''), NVL(address_line1, ''),
--                 NVL(city, ''), NVL(state, ''),
--                 NVL(postal_code, ''))) AS record_hash
--     FROM raw_db.crm.stg_customer_extract
-- ) src
--    ON tgt.customer_id = src.customer_id
--   AND tgt.is_current  = TRUE
-- WHEN MATCHED AND tgt.record_hash <> src.record_hash THEN
--     UPDATE SET tgt.effective_to = src.extract_ts,
--                tgt.is_current   = FALSE;
--
-- INSERT INTO gold_db.customers.dim_customers (
--     customer_id, customer_name, email, address_line1,
--     city, state, postal_code, effective_from, record_hash)
-- SELECT s.customer_id, s.customer_name, s.email, s.address_line1,
--        s.city, s.state, s.postal_code, s.extract_ts,
--        SHA2(CONCAT_WS('|', NVL(s.customer_name, ''),
--             NVL(s.email, ''), NVL(s.address_line1, ''),
--             NVL(s.city, ''), NVL(s.state, ''),
--             NVL(s.postal_code, '')))
-- FROM raw_db.crm.stg_customer_extract s
-- LEFT JOIN gold_db.customers.dim_customers t
--        ON t.customer_id = s.customer_id
--       AND t.is_current  = TRUE
-- WHERE t.customer_id IS NULL;
--
-- COMMIT;
--
-- Expected in the worksheet: number of rows updated: 2 after the MERGE (one
-- per moved customer; the new signup matched nothing), number of rows
-- inserted: 3 after the INSERT (two new versions, one first version).

-- Rollback, demonstrated: close the movers, then fail on purpose before the
-- insert. The handler rolls back, and the movers are still current afterwards.
-- Nothing this block does survives, so it is safe to run before the real pair.
EXECUTE IMMEDIATE $$
DECLARE
    closed NUMBER;
BEGIN
    BEGIN TRANSACTION;

    MERGE INTO gold_db.customers.dim_customers tgt
    USING (
        SELECT customer_id, extract_ts,
               SHA2(CONCAT_WS('|', NVL(customer_name, ''),
                    NVL(email, ''), NVL(address_line1, ''),
                    NVL(city, ''), NVL(state, ''),
                    NVL(postal_code, ''))) AS record_hash
        FROM raw_db.crm.stg_customer_extract
    ) src
       ON tgt.customer_id = src.customer_id
      AND tgt.is_current  = TRUE
    WHEN MATCHED AND tgt.record_hash <> src.record_hash THEN
        UPDATE SET tgt.effective_to = src.extract_ts,
                   tgt.is_current   = FALSE;

    closed := SQLROWCOUNT;
    SELECT 1 / 0;   -- stands in for an INSERT that fails halfway
    COMMIT;
    RETURN 'unreachable';
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN 'Rolled back after closing ' || closed || ' versions. Error was: ' || SQLERRM;
END;
$$;

-- Expected: 'Rolled back after closing 2 versions. Error was: Division by zero'.

SELECT COUNT(*) AS movers_still_current
  FROM gold_db.customers.dim_customers
 WHERE customer_id IN ('CUST-CH12-0007', 'CUST-CH12-0042')
   AND is_current;

-- Expected: 2. The close was undone with the failure; a COMMIT in its place
-- would have left 0 here.

-- The executable pair: guard, transaction, close, insert, commit, and a
-- ROLLBACK plus re-raise on any failure. This is the form a scheduled task or
-- a CoCo-generated loader should carry.
EXECUTE IMMEDIATE $$
DECLARE
    dup_keys NUMBER;
    closed   NUMBER;
    inserted NUMBER;
    duplicate_extract EXCEPTION (-20016, 'stg_customer_extract holds more than one row for a customer. Deduplicate the extract before applying it.');
BEGIN
    SELECT COUNT(*) - COUNT(DISTINCT customer_id)
      INTO :dup_keys
      FROM raw_db.crm.stg_customer_extract;
    IF (dup_keys > 0) THEN
        RAISE duplicate_extract;
    END IF;

    BEGIN TRANSACTION;

    MERGE INTO gold_db.customers.dim_customers tgt
    USING (
        SELECT customer_id, extract_ts,
               SHA2(CONCAT_WS('|', NVL(customer_name, ''),
                    NVL(email, ''), NVL(address_line1, ''),
                    NVL(city, ''), NVL(state, ''),
                    NVL(postal_code, ''))) AS record_hash
        FROM raw_db.crm.stg_customer_extract
    ) src
       ON tgt.customer_id = src.customer_id
      AND tgt.is_current  = TRUE
    WHEN MATCHED AND tgt.record_hash <> src.record_hash THEN
        UPDATE SET tgt.effective_to = src.extract_ts,
                   tgt.is_current   = FALSE;

    closed := SQLROWCOUNT;

    INSERT INTO gold_db.customers.dim_customers (
        customer_id, customer_name, email, address_line1,
        city, state, postal_code, effective_from, record_hash)
    SELECT s.customer_id, s.customer_name, s.email, s.address_line1,
           s.city, s.state, s.postal_code, s.extract_ts,
           SHA2(CONCAT_WS('|', NVL(s.customer_name, ''),
                NVL(s.email, ''), NVL(s.address_line1, ''),
                NVL(s.city, ''), NVL(s.state, ''),
                NVL(s.postal_code, '')))
    FROM raw_db.crm.stg_customer_extract s
    LEFT JOIN gold_db.customers.dim_customers t
           ON t.customer_id = s.customer_id
          AND t.is_current  = TRUE
    WHERE t.customer_id IS NULL;

    inserted := SQLROWCOUNT;
    COMMIT;
    RETURN 'Type 2 pair committed: closed ' || closed || ', inserted ' || inserted || '.';
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

-- Expected: 'Type 2 pair committed: closed 2, inserted 3.' Run the block again
-- and it reports closed 0, inserted 0, which is the idempotency test: a
-- replayed extract changes nothing.

-- The Type 2 signature: a closed row whose effective_to equals the new row's
-- effective_from, and one current row with the 9999-12-31 sentinel.
SELECT customer_id, is_current, effective_from, effective_to, city, state
  FROM gold_db.customers.dim_customers
 WHERE customer_id IN (SELECT customer_id FROM raw_db.crm.stg_customer_extract)
 ORDER BY customer_id, effective_from;

-- Expected: five rows. CUST-CH12-0007 and CUST-CH12-0042 each show a closed
-- version (is_current FALSE, effective_to 2026-03-01 06:00:00) and a current FL
-- version; CUST-CH14-0001 shows one current row.


-- =============================================================================
-- 3.4 Querying history with point-in-time joins
-- -----------------------------------------------------------------------------
-- The lab retains customer_id on the fact and resolves a version at query
-- time. A conventional dimensional fact loader resolves and stores the
-- applicable customer_key for an equality join instead. This fixture uses
-- extract_ts as its business-effective boundary; that assumption is required
-- for the query to represent where the customer lived at payment time.
-- Each fact row matches the one version whose validity window contains the
-- event timestamp. Half-open windows (inclusive effective_from, exclusive
-- effective_to) put a version boundary in one window, never two. The LEFT JOIN
-- with an 'unknown' bucket keeps the grand total intact: a payment that
-- precedes the first known version of its customer (a dimension loaded after
-- its facts, which the Chapter 5 fixture does for a handful of rows) lands in
-- 'unknown' instead of disappearing.
-- =============================================================================

SELECT NVL(d.state, 'unknown') AS state,
       SUM(IFF(ft.status IN ('COMPLETED', 'REFUNDED'),
               ft.amount, 0)) AS captured_amount
FROM gold_db.transactions.fact_transactions ft
LEFT JOIN gold_db.customers.dim_customers d
  ON d.customer_id = ft.customer_id
 AND ft.transaction_ts >= d.effective_from
 AND ft.transaction_ts <  d.effective_to
GROUP BY NVL(d.state, 'unknown')
ORDER BY captured_amount DESC;

-- Expected: one row per billing state plus, with the stock fixture, a small
-- 'unknown' row for the Chapter 5 payments that precede their customers'
-- first version. FL appears for the first time: the movers' payments from
-- 2026-03-01 onward now count toward Florida.

-- The grand total must equal the current-slice total, because every fact row
-- matches one version (or the unknown bucket) in each variant. Only the
-- distribution across states moves.
SELECT
    (SELECT SUM(IFF(ft.status IN ('COMPLETED', 'REFUNDED'), ft.amount, 0))
       FROM gold_db.transactions.fact_transactions ft
       LEFT JOIN gold_db.customers.dim_customers d
         ON d.customer_id = ft.customer_id
        AND ft.transaction_ts >= d.effective_from
        AND ft.transaction_ts <  d.effective_to)              AS pit_total,
    (SELECT SUM(IFF(ft.status IN ('COMPLETED', 'REFUNDED'), ft.amount, 0))
       FROM gold_db.transactions.fact_transactions ft
       LEFT JOIN gold_db.customers.dim_customers_current c
         ON c.customer_id = ft.customer_id)                   AS current_total;

-- Expected: pit_total = current_total to the cent. A difference means the
-- dimension's invariants are broken (overlapping windows double-count; a gap
-- moves rows into 'unknown' without moving the total); the invariants view in
-- chapter14_4_coco.sql finds which.

-- The movers, both ways: current-slice reports all their spending as FL,
-- point-in-time splits it at the move.
SELECT ft.customer_id,
       NVL(d.state, 'unknown') AS state_at_payment,
       COUNT(*)                AS payments
FROM gold_db.transactions.fact_transactions ft
LEFT JOIN gold_db.customers.dim_customers d
  ON d.customer_id = ft.customer_id
 AND ft.transaction_ts >= d.effective_from
 AND ft.transaction_ts <  d.effective_to
WHERE ft.customer_id IN ('CUST-CH12-0007', 'CUST-CH12-0042')
GROUP BY ft.customer_id, NVL(d.state, 'unknown')
ORDER BY ft.customer_id, state_at_payment;

-- Expected: two rows per mover, the pre-move state and FL, with the FL count
-- covering payments from March 2026 onward.


-- =============================================================================
-- 3.5 Tracking alternate values with Type 3
-- -----------------------------------------------------------------------------
-- A planned transition where reports need both values side by side for a
-- while: the legacy 'electronics' category folds into 'retail'. Two columns and
-- a MERGE cover it. One prior value supports alternate classifications of
-- the same payments. It does not retain a sequence of event-time categories;
-- that reporting question needs a history model such as Type 2.
-- IF NOT EXISTS keeps the column additions safe to rerun (Snowflake accepts it
-- on ADD COLUMN when no DEFAULT or AUTOINCREMENT is declared).
-- =============================================================================

ALTER TABLE gold_db.merchants.dim_merchants
    ADD COLUMN IF NOT EXISTS previous_category VARCHAR;
ALTER TABLE gold_db.merchants.dim_merchants
    ADD COLUMN IF NOT EXISTS category_changed_at TIMESTAMP_NTZ;

MERGE INTO gold_db.merchants.dim_merchants tgt
USING raw_db.partners.stg_merchant_reclass src
   ON tgt.merchant_id = src.merchant_id
WHEN MATCHED AND tgt.merchant_category IS DISTINCT FROM src.new_category THEN
    UPDATE SET tgt.previous_category   = tgt.merchant_category,
               tgt.merchant_category   = src.new_category,
               tgt.category_changed_at = src.reclass_ts;

-- Expected: number of rows updated: 2, one per electronics merchant: the
-- Chapter 5 pair MERCH_ELEC_1 and MERCH_ELEC_2 with the stock fixture, or the
-- chapter-owned MERCH-CH14-ELEC01 and MERCH-CH14-ELEC02 that the setup adds
-- when the dimension has no electronics merchant. Re-run: zero, since the
-- category already equals 'retail'.

-- Both rollups on demand: unchanged merchants carry a NULL prior value, so
-- NVL falls through to the current category for them.
SELECT NVL(previous_category, merchant_category) AS category_before,
       merchant_category                          AS category_after,
       COUNT(*)                                   AS merchants
  FROM gold_db.merchants.dim_merchants
 GROUP BY 1, 2
 ORDER BY 1, 2;

-- Expected: the 'electronics' row reports 'retail' as category_after; every
-- other category maps to itself.


-- =============================================================================
-- Section 3 validation set
-- =============================================================================

SELECT 'type1_new_merchant_present' AS check_name,
       COUNT(*) = 1 AS passed
  FROM gold_db.merchants.dim_merchants
 WHERE merchant_id = 'MERCH-CH14-NEW01'
UNION ALL
SELECT 'type1_corrections_applied',
       COUNT(*) = 3
  FROM gold_db.merchants.dim_merchants m
  JOIN raw_db.partners.stg_merchant_updates s
    ON s.merchant_id = m.merchant_id
 WHERE m.merchant_id LIKE 'MERCH-CH12-%'
   AND m.merchant_category = s.merchant_category
   AND m.merchant_city     = s.merchant_city
UNION ALL
SELECT 'type2_movers_have_two_versions',
       COUNT(*) = 4
  FROM gold_db.customers.dim_customers
 WHERE customer_id IN ('CUST-CH12-0007', 'CUST-CH12-0042')
UNION ALL
SELECT 'type2_one_current_per_customer',
       COUNT(*) = 0
  FROM (SELECT customer_id
          FROM gold_db.customers.dim_customers
         GROUP BY customer_id
        HAVING COALESCE(COUNT_IF(is_current), 0) <> 1)
UNION ALL
SELECT 'type3_reclass_applied',
       COUNT(*) = 0
  FROM gold_db.merchants.dim_merchants
 WHERE UPPER(merchant_category) = 'ELECTRONICS';

-- Expected: five rows, every passed = TRUE. Continue with
-- chapter14_3_data_vault.sql (optional) or chapter14_4_coco.sql.
