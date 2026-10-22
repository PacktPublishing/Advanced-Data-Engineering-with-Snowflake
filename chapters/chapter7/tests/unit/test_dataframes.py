"""Section 5.1: DataFrame unit tests against the local Snowpark engine."""

from __future__ import annotations

from snowflake.snowpark.functions import col, sum as sf_sum
from snowflake.snowpark.types import (
    FloatType,
    StringType,
    StructField,
    StructType,
)


def _make_transactions(local_session):
    schema = StructType(
        [
            StructField("transaction_id", StringType()),
            StructField("customer_id", StringType()),
            StructField("merchant_id", StringType()),
            StructField("amount", FloatType()),
            StructField("status", StringType()),
        ]
    )
    rows = [
        ("T1", "C1", "M1", 100.0, "COMPLETED"),
        ("T2", "C1", "M1", 50.0, "PENDING"),
        ("T3", "C2", "M1", 200.0, "COMPLETED"),
        ("T4", "C2", "M2", 150.0, "COMPLETED"),
        ("T5", "C3", "M2", 25.0, "FAILED"),
    ]
    return local_session.create_dataframe(rows, schema=schema)


def test_filter_pushes_completed_only(local_session):
    df = _make_transactions(local_session)
    completed = df.filter(col("status") == "COMPLETED")

    assert completed.count() == 3
    assert {r["TRANSACTION_ID"] for r in completed.collect()} == {"T1", "T3", "T4"}


def test_groupby_aggregate_per_merchant(local_session):
    df = _make_transactions(local_session)
    per_merchant = (
        df.filter(col("status") == "COMPLETED")
        .group_by("merchant_id")
        .agg(sf_sum("amount").alias("revenue"))
        .order_by("merchant_id")
    )

    rows = per_merchant.collect()
    assert [(r["MERCHANT_ID"], r["REVENUE"]) for r in rows] == [
        ("M1", 300.0),
        ("M2", 150.0),
    ]


def test_join_drops_orphans(local_session):
    customers = local_session.create_dataframe(
        [("C1", "Alice"), ("C2", "Bob")],
        schema=StructType(
            [
                StructField("customer_id", StringType()),
                StructField("customer_name", StringType()),
            ]
        ),
    )
    transactions = _make_transactions(local_session)

    joined = (
        transactions.filter(col("status") == "COMPLETED")
        .join(customers, on="customer_id", how="inner")
        .select("transaction_id", "customer_name")
        .order_by("transaction_id")
    )

    rows = joined.collect()
    assert [r["TRANSACTION_ID"] for r in rows] == ["T1", "T3", "T4"]
