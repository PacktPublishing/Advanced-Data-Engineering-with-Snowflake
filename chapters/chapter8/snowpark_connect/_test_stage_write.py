"""Probe: write to stage from Snowpark Connect (read a table, write Parquet out)."""
from snowflake import snowpark_connect

spark = snowpark_connect.init_spark_session()

txns = spark.read.table("gold_db.transactions.fact_transactions")
print(f"Table rows: {txns.count()}")

txns.limit(5).write.mode("overwrite").parquet(
    "@gold_db.transactions.lake_stage/settlements/2026/06/"
)
print("Write to stage succeeded")
