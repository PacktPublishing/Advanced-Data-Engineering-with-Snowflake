"""Chapter 8, Section 3.1: first-wave TechFlow settlement job.

Aggregates settled transactions per merchant per day. The Spark original read
Parquet from the lake and wrote Parquet back; the migrated version reads the
table the data already lands in and writes a table, which is the smaller diff
and the version that needs no save-mode rework.

Column names match the companion gold_db.transactions.fact_transactions built
in Chapters 4 to 5 (AMOUNT, TRANSACTION_TS, STATUS = 'COMPLETED'). The chapter
prose now uses these same names; the settled_* identifiers below are output
aliases for the settlement result, not input columns.

Notice what did NOT change from the Spark original: the session builder, the
transformations, and the write call are stock PySpark. Snowpark Submit handles
the connection wiring, so this script contains no Snowflake imports and stays
runnable against a plain Spark cluster during the parallel-run window the
parity discipline (Section 2.4) needs.

Run it through Snowpark Submit, not directly:
    snowpark-submit \\
      --snowflake-workload-name DAILY_SETTLEMENT \\
      --snowflake-connection-name spark-connect \\
      --compute-pool TECHFLOW_SPARK_POOL \\
      --wait-for-completion \\
      jobs/daily_settlement.py
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as sf_sum, count, to_date

spark = SparkSession.builder.appName("daily_settlement").getOrCreate()

txns = spark.read.table("gold_db.transactions.fact_transactions")

settlement = (
    txns.filter(col("status") == "COMPLETED")
    .withColumn("settle_date", to_date(col("transaction_ts")))
    .groupBy("merchant_id", "settle_date")
    .agg(
        sf_sum("amount").alias("settled_amount_usd"),
        count("*").alias("settled_txn_count"),
    )
)

settlement.write.mode("overwrite").saveAsTable(
    "gold_db.transactions.daily_settlement"
)

spark.stop()
