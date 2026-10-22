-- =============================================================================
-- Chapter 14 teardown - reverses everything Chapter 14 created or changed, and
-- nothing else. No DROP SCHEMA on any shared schema: every shared object is
-- named explicitly, and only the two chapter-owned schemas (gold_db.calendar,
-- raw_db.partners) and the chapter-owned vault_db are dropped whole, after
-- their named objects. Note that DROP SCHEMA ... RESTRICT in Snowflake only
-- refuses schemas whose keys are referenced by foreign keys elsewhere; it does
-- not protect stray objects, so nothing else should be created in those two
-- schemas. Each of those two schemas is dropped inside a block that first
-- checks the schema exists, because DROP TABLE IF EXISTS still fails when the
-- schema itself is missing, as it is on an account where the setup never ran.
--
-- Order matters: the section 6 comments and view first, then the star objects
-- and their constraints (the FK must go before the PK it references), then
-- the two shared dimensions are restored, then the fixtures, the simulated
-- source extracts, and vault_db.
--
-- Safe to run after any subset of the section files, including none: every
-- statement that targets an object a skipped section never created uses
-- IF EXISTS, the constraint drops run inside a block that checks
-- TABLE_CONSTRAINTS first, and the dim_merchants restore and the two
-- chapter-owned schema drops run inside blocks that first check their objects
-- exist. The restore needs the setup's snapshot, so run this file before
-- dropping raw_db.partners by hand.
--
-- Role convention: SYSADMIN throughout.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- -----------------------------------------------------------------------------
-- Section 6: the invariants view and the grain comments
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS gold_db.customers.dim_customers_invariants;

-- The grain comments: neither Chapter 5 nor Chapter 12 commented these tables
-- or columns, so unsetting them restores the earlier state. dim_date, the star
-- view, and previous_category go with their objects below.
ALTER TABLE gold_db.transactions.fact_transactions UNSET COMMENT;
ALTER TABLE gold_db.transactions.fact_refunds UNSET COMMENT;
ALTER TABLE gold_db.customers.dim_customers UNSET COMMENT;
ALTER TABLE gold_db.merchants.dim_merchants UNSET COMMENT;
ALTER TABLE gold_db.customers.dim_customers ALTER COLUMN effective_from UNSET COMMENT;
ALTER TABLE gold_db.customers.dim_customers ALTER COLUMN effective_to UNSET COMMENT;
ALTER TABLE gold_db.customers.dim_customers ALTER COLUMN record_hash UNSET COMMENT;


-- -----------------------------------------------------------------------------
-- Section 2: star view, constraints, calendar
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS gold_db.transactions.star_transactions;

-- DROP CONSTRAINT has no IF EXISTS form, so the block checks TABLE_CONSTRAINTS
-- before each drop and runs clean whether or not section 2 ran. FK before PK:
-- the foreign key references pk_dim_merchants. pk_fact_transactions belongs to
-- Chapter 5; only the trust added here comes off.
EXECUTE IMMEDIATE $$
DECLARE
    fk_present NUMBER;
    pk_present NUMBER;
BEGIN
    SELECT COUNT(*) INTO :fk_present
      FROM gold_db.information_schema.table_constraints
     WHERE table_schema = 'TRANSACTIONS' AND table_name = 'FACT_TRANSACTIONS'
       AND constraint_name = 'FK_TXN_MERCHANT';
    IF (fk_present > 0) THEN
        ALTER TABLE gold_db.transactions.fact_transactions
            DROP CONSTRAINT fk_txn_merchant;
    END IF;
    SELECT COUNT(*) INTO :pk_present
      FROM gold_db.information_schema.table_constraints
     WHERE table_schema = 'MERCHANTS' AND table_name = 'DIM_MERCHANTS'
       AND constraint_name = 'PK_DIM_MERCHANTS';
    IF (pk_present > 0) THEN
        ALTER TABLE gold_db.merchants.dim_merchants
            DROP CONSTRAINT pk_dim_merchants;
    END IF;
    ALTER TABLE gold_db.transactions.fact_transactions
        MODIFY CONSTRAINT pk_fact_transactions NORELY;
    RETURN 'Section 2 constraints removed (FK: ' || fk_present
           || ', PK: ' || pk_present || '), pk_fact_transactions set to NORELY.';
END;
$$;

-- Expected: 'Section 2 constraints removed (FK: 1, PK: 1), ...' after a full
-- run, or (FK: 0, PK: 0) if section 2 was skipped.

-- pk_dim_date goes with its table.
EXECUTE IMMEDIATE $$
DECLARE
    calendar_present NUMBER;
BEGIN
    SELECT COUNT(*) INTO :calendar_present
      FROM gold_db.information_schema.schemata
     WHERE schema_name = 'CALENDAR';
    IF (calendar_present = 0) THEN
        RETURN 'gold_db.calendar not present, nothing to drop.';
    END IF;
    DROP TABLE IF EXISTS gold_db.calendar.dim_date;
    DROP SCHEMA IF EXISTS gold_db.calendar;
    RETURN 'gold_db.calendar and dim_date dropped.';
END;
$$;


-- -----------------------------------------------------------------------------
-- Section 3: restore the two shared dimensions
-- -----------------------------------------------------------------------------
-- dim_merchants: drop the Type 3 columns, remove the new merchant, and put
-- only the merchants the fixtures touched back from the snapshot the setup
-- took before any change. Limiting the restore to the fixture ids keeps any
-- edit you made to other merchants in between.
ALTER TABLE gold_db.merchants.dim_merchants
    DROP COLUMN IF EXISTS previous_category, category_changed_at;

DELETE FROM gold_db.merchants.dim_merchants
 WHERE merchant_id LIKE 'MERCH-CH14-%';

EXECUTE IMMEDIATE $$
DECLARE
    snapshot_present NUMBER;
BEGIN
    SELECT COUNT(*) INTO :snapshot_present
      FROM raw_db.information_schema.tables
     WHERE table_schema = 'PARTNERS'
       AND table_name   = 'DIM_MERCHANTS_BEFORE_CH14';
    IF (snapshot_present = 0) THEN
        RETURN 'No setup snapshot found, so dim_merchants needs no restore.';
    END IF;
    UPDATE gold_db.merchants.dim_merchants m
       SET merchant_name     = b.merchant_name,
           merchant_category = b.merchant_category,
           merchant_city     = b.merchant_city
      FROM raw_db.partners.dim_merchants_before_ch14 b
     WHERE m.merchant_id = b.merchant_id
       AND b.merchant_id IN (SELECT merchant_id FROM raw_db.partners.stg_merchant_updates
                             UNION
                             SELECT merchant_id FROM raw_db.partners.stg_merchant_reclass);
    RETURN 'dim_merchants restored from the setup snapshot: ' || SQLROWCOUNT || ' rows updated.';
END;
$$;

-- Expected: 'dim_merchants restored from the setup snapshot: 5 rows updated.'
-- with the stock fixture (three Type 1 corrections and two Type 3
-- reclassifications; if section 3 never ran, the same 5 rows update to
-- identical values), 3 rows when the setup had to add its own electronics
-- pair (those two carry MERCH-CH14- ids and went with the DELETE above), or
-- the no-snapshot message if the setup never ran.

-- dim_customers: delete the versions section 3 inserted (fixed ids, fixed
-- effective_from), then reopen the two seeded versions it closed.
DELETE FROM gold_db.customers.dim_customers
 WHERE customer_id LIKE 'CUST-CH14-%'
    OR (customer_id IN ('CUST-CH12-0007', 'CUST-CH12-0042')
        AND effective_from = '2026-03-01 06:00:00'::TIMESTAMP_NTZ);

UPDATE gold_db.customers.dim_customers
   SET is_current   = TRUE,
       effective_to = '9999-12-31'::TIMESTAMP_NTZ
 WHERE customer_id IN ('CUST-CH12-0007', 'CUST-CH12-0042')
   AND record_hash = 'CH12-SEED';

-- Expected: 3 rows deleted, 2 rows updated.

-- Prove the dimension is back to one current row per customer.
SELECT COUNT(*) AS customers_with_current_count_not_one
  FROM (SELECT customer_id
          FROM gold_db.customers.dim_customers
         GROUP BY customer_id
        HAVING COALESCE(COUNT_IF(is_current), 0) <> 1);

-- Expected: 0.


-- -----------------------------------------------------------------------------
-- Setup: fixtures and the snapshot
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS raw_db.crm.stg_customer_extract;
DROP TABLE IF EXISTS raw_db.crm.customer_history;
EXECUTE IMMEDIATE $$
DECLARE
    partners_present NUMBER;
BEGIN
    SELECT COUNT(*) INTO :partners_present
      FROM raw_db.information_schema.schemata
     WHERE schema_name = 'PARTNERS';
    IF (partners_present = 0) THEN
        RETURN 'raw_db.partners not present, nothing to drop.';
    END IF;
    DROP TABLE IF EXISTS raw_db.partners.stg_merchant_updates;
    DROP TABLE IF EXISTS raw_db.partners.stg_merchant_reclass;
    DROP TABLE IF EXISTS raw_db.partners.merchant_directory;
    DROP TABLE IF EXISTS raw_db.partners.dim_merchants_before_ch14;
    DROP SCHEMA IF EXISTS raw_db.partners;
    RETURN 'raw_db.partners fixtures, extract, snapshot, and schema dropped.';
END;
$$;
-- raw_db.crm is shared with Chapters 4 and 5 and stays; only the two
-- chapter-owned tables in it go.


-- -----------------------------------------------------------------------------
-- Section 4 (optional): the vault is chapter-owned, so the database goes
-- (its two source extracts were dropped with the fixtures above)
-- -----------------------------------------------------------------------------
DROP DATABASE IF EXISTS vault_db;

-- Chapter 14 leaves the shared gold tables as it found them: rows, columns,
-- constraints, and comments restored. The one trace is the customer_key
-- AUTOINCREMENT high-water mark, which the inserted and deleted versions
-- advanced and which cannot move backwards. To reproduce the chapter's expected
-- counts again, run chapter14_0_setup.sql and the section files in order.
