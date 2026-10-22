-- =====================================================================
-- Chapter 10, Section 4.2: Versioned migration with schemachange
-- =====================================================================
-- schemachange applies versioned scripts (V prefix) in order and records
-- each in ops_db.schemachange.change_history (see --change-history-table
-- in the chapter deploy command). This runs once and never again unless
-- you ship a higher version.
--
-- Both objects live in shared, unsuffixed layers so one migration serves
-- both environments:
--   * pipeline_run_log - the finalizer audit table from Chapter 9
--   * new_txn_stream    - a stream, which the DCM preview cannot yet manage
--
-- CREATE ... IF NOT EXISTS makes the script a safe baseline against objects
-- that already exist; it does not verify the live object's shape matches.
-- =====================================================================

CREATE TABLE IF NOT EXISTS ops_db.pipelines.pipeline_run_log (
    logged_at         TIMESTAMP_NTZ,
    graph_name        STRING,
    failed_task_count NUMBER
);

CREATE STREAM IF NOT EXISTS raw_db.streaming.new_txn_stream
    ON TABLE raw_db.streaming.raw_transactions
    APPEND_ONLY = TRUE
    SHOW_INITIAL_ROWS = FALSE;
