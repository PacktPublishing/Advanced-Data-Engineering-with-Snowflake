"""Chapter 8, Section 2.2: the type-coercion gap family, one column.

Snowpark Connect represents ByteType, ShortType, and IntegerType as LongType,
and it infers a literal None as StringType because Snowflake has no NullType.
The query results are semantically correct, but the schemas differ from native
Spark, and any comparison tooling that checks schemas byte for byte reports
failures on perfectly good migrations.

With Snowpark Connect, `spark.range(1).select(col("id").cast("int"), lit(None))`
followed by printSchema() reports `int_col: long` and `null_col: string`. Spark
Connect sends an analyze request to the server, so Snowflake's resolved types
come back on printSchema() even though the plan is not materialized. Native
PySpark, with no Snowpark Connect server, would report `int_col: integer` and
`null_col: void`.

The parity harness in parity/parity_signature.py normalizes types on both sides
before comparing for exactly this reason.

Run with:  python -m snowpark_connect.type_coercion_demo
"""

from snowflake import snowpark_connect
from pyspark.sql.functions import col, lit

spark = snowpark_connect.init_spark_session()

# Snowpark Connect resolves the schema on the Snowflake side, so printSchema()
# shows the coerced types: int -> long, None -> string.
df = spark.range(1).select(
    col("id").cast("int").alias("int_col"),
    lit(None).alias("null_col"),
)
print("snowpark connect resolved schema:")
df.printSchema()
