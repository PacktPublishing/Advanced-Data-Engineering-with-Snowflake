-- Chapter 11, Section 1.5: load the partition's fraud-score file.
--
-- Same COPY as load_fraud_scores.sql, keyed on the run's partition rather than
-- its data interval, because a partitioned DAG has no data interval.
-- {{ partition_date | ds }} formats the resolved partition as YYYY-MM-DD and
-- requires Airflow 3.3+; on 3.2 use {{ dag_run.partition_key }} instead, which
-- returns the raw key and therefore depends on the producer's key_format.
--
-- COPY load metadata (retained 64 days) makes a rerun of the same partition a
-- no-op, which is what keeps the load idempotent under replay.
--
-- REVIEW ONLY for static validation: this file is read, never executed.
COPY INTO raw_db.streaming.fraud_scores
FROM @raw_db.streaming.ml_scores_stage
FILES = ('fraud_scores_{{ partition_date | ds }}.parquet')
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
