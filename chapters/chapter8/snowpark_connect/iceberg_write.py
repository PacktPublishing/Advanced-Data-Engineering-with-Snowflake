"""Chapter 8, Section 4.4: working with Iceberg tables from Spark code.

Snowpark Connect works with Iceberg tables in both directions. Reads need no
special handling: a spark.read.table() against an Iceberg table behaves like any
other table.

The limits are specific:
  * Time travel through Snowpark Connect is not supported in any form (no
    snapshots, branch reads, or incremental reads), regardless of who manages
    the table. Use the Time Travel and stream patterns from earlier chapters
    against native tables instead.
  * Creating tables through Spark SQL is not supported.
  * Writing to a Snowflake-managed Iceberg table uses the writeTo() API, not
    the regular saveAsTable() which is restricted to FDN (regular) tables.
  * The Iceberg table must be pre-created (DDL) with CATALOG='SNOWFLAKE' and
    an EXTERNAL_VOLUME + BASE_LOCATION. Snowpark Connect does not create
    Iceberg tables from saveAsTable on non-CLD databases.

Run with:  python -m snowpark_connect.iceberg_write
"""

from snowflake import snowpark_connect

spark = snowpark_connect.init_spark_session()

# Assume `settlement` was produced upstream by the migrated job.
settlement = spark.read.table("gold_db.transactions.daily_settlement")

# writeTo() is the V2 DataSource API that Snowpark Connect uses for Iceberg.
# overwritePartitions() replaces matching partitions (or all data if unpartitioned).
settlement.writeTo(
    "gold_db.transactions.iceberg_daily_settlement"
).overwritePartitions()

print("Iceberg write complete")
