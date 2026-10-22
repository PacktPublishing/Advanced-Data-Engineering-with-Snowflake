"""Chapter 8, Section 5.2: replacing a UDF with a pushdown-friendly CASE.

The settlement job's Spark original carried a @udf that classified transaction
amounts into bands with a chain of if statements. The migrated version replaces
it with a CASE expression through when(), which pushes down, vectorizes, and
removes the UDF's null-semantics risk in one move.

The rewrite is worth the diff noise whenever the UDF logic expresses as SQL.
UDFs carrying a regex library or a domain calculation with no SQL equivalent
follow the Chapter 7 vectorized UDF guidance instead. Confirm the result with
explain() during development and Query Profile after deployment.

Run with:  python -m snowpark_connect.amount_band
"""

from snowflake import snowpark_connect
from pyspark.sql.functions import when, col

spark = snowpark_connect.init_spark_session()

txns = spark.read.table("gold_db.transactions.fact_transactions")

# Source column is AMOUNT in the companion table; the chapter prose calls it
# amount_usd. The CASE logic is identical either way.
banded = txns.withColumn(
    "amount_band",
    when(col("amount") >= 10000, "LARGE")
    .when(col("amount") >= 1000, "MEDIUM")
    .otherwise("SMALL"),
)

banded.explain()
banded.show(5)
