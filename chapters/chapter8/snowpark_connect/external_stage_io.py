"""Chapter 8, Section 4.1: reading and writing through external stages.

The stage reference replaces the URI scheme and bucket, and the rest of the
path survives. The storage integration behind @lake_stage holds the IAM trust
relationship, so the access keys that used to live in Spark configuration
disappear from the codebase. The chapter uses the short name @lake_stage for
readability; this file uses the fully qualified @gold_db.transactions.lake_stage
so it runs regardless of the session's current database and schema.

File writes support overwrite semantics but not Append or Ignore modes, so
appending jobs restructure before they migrate.

NOTE: A bare spark.read.parquet("@stage/dir/") returns 0 rows because Snowpark
Connect does not auto-list directory contents. Add .option("PATTERN", ".*")
to enable Snowflake's PATTERN clause, which resolves the listing correctly.

Run with:  python -m snowpark_connect.external_stage_io
"""

from snowflake import snowpark_connect

spark = snowpark_connect.init_spark_session()

# Spark original
# txns = spark.read.parquet("s3a://techflow-lake/transactions/2026/06/")

# Migrated: same files, read through the external stage.
# The PATTERN option is required for Snowpark Connect to list directory contents.
txns = (
    spark.read.format("parquet")
    .option("PATTERN", ".*parquet.*")
    .load("@gold_db.transactions.lake_stage/transactions/2026/06/")
)

print(f"Rows read from stage: {txns.count()}")
txns.show(5)

# Cast TIMESTAMP_LTZ columns to NTZ before writing — Snowflake cannot unload
# LTZ/TZ types to Parquet directly.
from pyspark.sql.functions import col

result = txns.select(
    *[
        col(c).cast("timestamp_ntz") if "TS" in c or "AT" in c else col(c)
        for c in txns.columns
    ]
)

# Writes use the same stage path form
result.write.mode("overwrite").parquet(
    "@gold_db.transactions.lake_stage/settlements/2026/06/"
)
print("Write to @gold_db.transactions.lake_stage/settlements/2026/06/ succeeded")
