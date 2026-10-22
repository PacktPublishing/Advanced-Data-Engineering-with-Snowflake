-- =====================================================================
-- Chapter 10, Sections 3.4 and 4.2: Shared stream in versioned native SQL
-- =====================================================================
-- Prerequisite: Chapter 9 raw_db.streaming.raw_transactions and BOOK_WH.
-- Run with DCM_PROD_DEPLOYER after granting it the required schema/table
-- privileges and ownership of the existing shared stream. No placeholders.
-- The CI template selects Snowflake CLI 3.26.0; SQL is unchanged in this round.
--
-- DEFINE STREAM is supported in open preview as of September 2026. This
-- chapter keeps the shared stream outside both DCM targets by choice.
-- Run this file from the reviewed commit; the CI workflow uses snow sql -f.
-- IF NOT EXISTS preserves the offset of an existing stream, but does not
-- verify that its properties match. Review SHOW STREAMS before adoption.
-- Do not also manage this stream through the optional legacy migration.
-- =====================================================================

CREATE STREAM IF NOT EXISTS raw_db.streaming.new_txn_stream
    ON TABLE raw_db.streaming.raw_transactions
    APPEND_ONLY = TRUE
    SHOW_INITIAL_ROWS = FALSE;
