"""Chapter 8, Section 1.3, step 3: development environment smoke test.

The count and the small aggregation both execute on BOOK_WH, and both appear in
Snowsight's query history attributed to our role. That query history entry is
the verification: if the queries show up there, the plan is reaching Snowflake
and we are not accidentally running a local Spark in disguise.

Run with:  python -m snowpark_connect.smoke_test
"""

from snowflake import snowpark_connect

spark = snowpark_connect.init_spark_session()

transactions = spark.read.table("fact_transactions")
print(transactions.count())
transactions.groupBy("merchant_id").count().show(5)
