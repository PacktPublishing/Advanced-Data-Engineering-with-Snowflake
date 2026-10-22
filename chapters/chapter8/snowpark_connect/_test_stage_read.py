"""Quick probe: test stage read through Snowpark Connect."""
from snowflake import snowpark_connect

spark = snowpark_connect.init_spark_session()

# Try various path forms
paths = [
    "@gold_db.transactions.lake_stage/transactions/2026/06/",
    "@gold_db.transactions.lake_stage/transactions/2026/06",
    "@gold_db.transactions.lake_stage/transactions/",
]
for p in paths:
    try:
        df = spark.read.parquet(p)
        cnt = df.count()
        print(f"  {p} -> {cnt} rows")
        if cnt > 0:
            df.show(2)
            break
    except Exception as e:
        print(f"  {p} -> ERROR: {e!r}")
