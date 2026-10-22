"""SQL constants shared by the Chapter 11 Dagster assets.

These hold the same statements the Airflow project keeps in ``.sql`` files and
the Prefect flow keeps as module constants. Importing this module runs nothing;
the asset bodies bind the run's partition into them at materialization time.

Every statement is scoped to one day, so rematerializing a partition replaces
exactly that partition and leaves every other day untouched.

Two binding styles appear here, and the difference is not cosmetic. Most
statements bind the date as a query parameter (``%(run_date)s``), which is the
safe default. COPY INTO cannot: its FILES clause takes string literals only and
rejects an expression, so the file name is interpolated in Python instead. The
partition key comes from Dagster's own DailyPartitionsDefinition and the asset
revalidates it as a date before formatting, so nothing unchecked reaches SQL.
"""

CLEANSE_SQL = "CALL ops_db.pipelines.run_cleanse()"

# The partition names the file, so a rematerialization loads that day and only
# that day. COPY's load metadata (64 days) makes reloading it a no-op.
COPY_SCORES_SQL = """
COPY INTO raw_db.streaming.fraud_scores
FROM @raw_db.streaming.ml_scores_stage
FILES = ('fraud_scores_{run_date}.parquet')
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
"""

# The partition-scoped rebuild is two statements, run inside one explicit
# transaction by the asset so the day is never half-written. They are separate
# constants because the Snowflake connector executes one statement per call
# unless multi-statement execution is enabled explicitly.
DELETE_REVENUE_SQL = """
DELETE FROM gold_db.transactions.merchant_daily_revenue
WHERE revenue_date = TO_DATE(%(run_date)s)
"""

INSERT_REVENUE_SQL = """
INSERT INTO gold_db.transactions.merchant_daily_revenue
SELECT merchant_id, DATE_TRUNC('day', transaction_ts) AS revenue_date,
       COUNT(*) AS transaction_count, SUM(amount) AS gross_revenue
FROM silver_db.transactions.transactions_clean
WHERE status = 'COMPLETED'
  AND DATE_TRUNC('day', transaction_ts) = TO_DATE(%(run_date)s)
GROUP BY 1, 2
"""

# Both sides are scoped to the run's partition. Without the scored_date
# predicate the join fans out: fraud_scores keeps one row per merchant per
# scored day, so after a week every high-risk merchant would appear seven times.
SEGMENT_SQL = """
SELECT r.merchant_id, r.gross_revenue, s.risk_score
FROM gold_db.transactions.merchant_daily_revenue r
JOIN raw_db.streaming.fraud_scores s USING (merchant_id)
WHERE s.risk_score > 0.8
  AND r.revenue_date = TO_DATE(%(run_date)s)
  AND s.scored_date = TO_DATE(%(run_date)s)
"""
