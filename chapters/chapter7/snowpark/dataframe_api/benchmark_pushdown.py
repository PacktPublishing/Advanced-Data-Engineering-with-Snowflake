"""Section 1.2 supporting benchmark: pushdown vs early ``to_pandas``.

The chapter references a benchmark that runs the same monthly-revenue logic
three ways. This script implements the first two paths so the reader can
reproduce the numbers locally:

1. Pure Snowpark DataFrame chain that pushes everything down.
2. Snowpark with an early ``to_pandas()`` that pulls the table to the laptop
   before the aggregation runs.

The third path (bare pandas + Snowflake connector) is intentionally omitted
because it routinely fails to complete on the same connection and would just
hang the script. Add it if you have a beefy laptop and want to time it.

Run with::

    python -m snowpark.dataframe_api.benchmark_pushdown --limit 5000000
"""

from __future__ import annotations

import argparse
import sys
import time

from snowflake.snowpark.functions import (
    col,
    current_date,
    date_trunc,
    dateadd,
    lit,
    sum as sf_sum,
)

from snowpark.session import build_session


def run_pushdown(session, row_limit: int) -> float:
    """Pure Snowpark: every operation pushes down to Snowflake."""
    start = time.perf_counter()
    rows = (
        session.table("fact_transactions")
        .limit(row_limit)
        .filter(col("status") == "COMPLETED")
        .filter(col("transaction_ts") >= dateadd("day", lit(-90), current_date()))
        .with_column("revenue_month", date_trunc("month", col("transaction_ts")))
        .group_by("merchant_id", "revenue_month")
        .agg(sf_sum("amount").alias("monthly_revenue"))
        .order_by("merchant_id", "revenue_month")
        .collect()
    )
    elapsed = time.perf_counter() - start
    print(f"[pushdown]      rows={len(rows):>8d}  elapsed={elapsed:6.2f}s")
    return elapsed


def run_early_to_pandas(session, row_limit: int) -> float:
    """Snowpark + early to_pandas: pulls every row to the laptop first."""
    start = time.perf_counter()
    laptop_df = (
        session.table("fact_transactions")
        .limit(row_limit)
        .to_pandas()
    )
    laptop_df = laptop_df[laptop_df["STATUS"] == "COMPLETED"]
    laptop_df["REVENUE_MONTH"] = laptop_df["TRANSACTION_TS"].dt.to_period("M")
    grouped = (
        laptop_df.groupby(["MERCHANT_ID", "REVENUE_MONTH"])["AMOUNT"]
        .sum()
        .reset_index(name="MONTHLY_REVENUE")
        .sort_values(["MERCHANT_ID", "REVENUE_MONTH"])
    )
    elapsed = time.perf_counter() - start
    print(f"[early_to_pandas] rows={len(grouped):>8d}  elapsed={elapsed:6.2f}s")
    return elapsed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--limit",
        type=int,
        default=1_000_000,
        help="Row limit applied to fact_transactions before each variant.",
    )
    args = parser.parse_args(argv)

    session = build_session()
    try:
        pushdown = run_pushdown(session, args.limit)
        early = run_early_to_pandas(session, args.limit)
        speedup = early / pushdown if pushdown > 0 else float("inf")
        print(f"speedup (early/pushdown) = {speedup:.1f}x")
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
