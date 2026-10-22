"""Section 1.2: Compose Snowpark DataFrame transformations with pushdown.

Computes per-merchant monthly revenue for completed transactions in the last
90 days. Every operation in the chain maps to a SQL operator the warehouse
executes; no rows leave Snowflake until :func:`DataFrame.show` runs.

Run with::

    python -m snowpark.dataframe_api.monthly_revenue
"""

from __future__ import annotations

import sys

from snowflake.snowpark.functions import (
    col,
    current_date,
    date_trunc,
    dateadd,
    lit,
    sum as sf_sum,
)

from snowpark.session import build_session


def build_monthly_revenue(session):
    """Return the lazy DataFrame; the caller decides when to materialize."""
    return (
        session.table("fact_transactions")
        .filter(col("status") == "COMPLETED")
        .filter(col("transaction_ts") >= dateadd("day", lit(-90), current_date()))
        .with_column("revenue_month", date_trunc("month", col("transaction_ts")))
        .group_by("merchant_id", "revenue_month")
        .agg(sf_sum("amount").alias("monthly_revenue"))
        .order_by("merchant_id", "revenue_month")
    )


def main() -> int:
    session = build_session()
    try:
        df = build_monthly_revenue(session)
        df.show(10)
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
