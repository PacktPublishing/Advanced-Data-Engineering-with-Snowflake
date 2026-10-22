-- Chapter 11, Section 1.3: load the run's dated fraud-score file.
-- Templated by Airflow; {{ ds }} resolves to the run's logical date (the
-- previous calendar day for a 02:00 run). COPY load metadata (64 days) makes a
-- rerun of the same interval a no-op, so the load is idempotent.
-- Static validation reads this file but never runs the COPY.
COPY INTO raw_db.streaming.fraud_scores
FROM @raw_db.streaming.ml_scores_stage
FILES = ('fraud_scores_{{ ds }}.parquet')
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
