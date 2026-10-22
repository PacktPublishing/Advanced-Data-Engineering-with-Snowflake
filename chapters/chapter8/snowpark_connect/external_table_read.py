"""Chapter 8, Section 4.2: reading Avro/ORC through an external table.

Avro and ORC are not supported in the Snowpark Connect read path, and no option
flag changes that. Define the external table once (see chapter8_setup.sql,
section 0.3) and let the Spark code read it like any other table.

The external table carries a VALUE variant column plus any virtual columns we
define, so jobs that relied on Avro schema fields adjust their column
references once. The same pattern covers ORC by changing the file format type.

Run with:  python -m snowpark_connect.external_table_read
"""

from snowflake import snowpark_connect

spark = snowpark_connect.init_spark_session()

# Replaces spark.read.format("avro").load(...) with a plain table read.
events = spark.read.table("gold_db.transactions.ext_payment_events")
events.printSchema()
events.show(5)
