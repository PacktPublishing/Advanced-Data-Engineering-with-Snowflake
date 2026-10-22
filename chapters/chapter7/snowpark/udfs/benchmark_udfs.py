"""Section 3.2: Benchmark scalar UDF vs vectorized UDF on ``fact_transactions``.

In the chapter's runs on a 200M-row sample on a Snowpark-optimized MEDIUM
warehouse, the scalar UDF averaged about 17 seconds and the vectorized UDF
about 47 seconds, so for this cheap row-wise logic the scalar version was
roughly 2.5x faster. Vectorization is not an automatic win: it pays off when
the per-row Python work is expensive (model inference, regex, JSON parsing),
not for simple numeric comparisons. Results shift with warehouse size, data
shape, and Snowflake version, so run this against your own data before
quoting any figure. (And for logic this simple, a plain SQL CASE expression
beats both UDF variants.)

Both UDFs must already be registered. Run::

    python -m snowpark.udfs.scalar_risk_tier
    python -m snowpark.udfs.vectorized_risk_tier
    python -m snowpark.udfs.benchmark_udfs --rows 5000000 --warehouse BOOK_WH_XS_SO
"""

from __future__ import annotations

import argparse
import sys
import time

from snowflake.snowpark.functions import call_udf, col

from snowpark.session import build_session


def time_udf(session, udf_name: str, row_limit: int) -> float:
    start = time.perf_counter()
    (
        session.table("fact_transactions")
        .limit(row_limit)
        .with_column(
            "risk_tier",
            call_udf(udf_name, col("risk_score"), col("amount")),
        )
        .group_by("risk_tier")
        .count()
        .collect()
    )
    return time.perf_counter() - start


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", type=int, default=1_000_000)
    parser.add_argument("--warehouse", default="BOOK_WH")
    args = parser.parse_args(argv)

    session = build_session(warehouse=args.warehouse)
    try:
        scalar = time_udf(session, "classify_risk_tier", args.rows)
        vector = time_udf(session, "classify_risk_tier_vec", args.rows)
        speedup = scalar / vector if vector > 0 else float("inf")
        print(
            f"warehouse={args.warehouse} rows={args.rows:,d}\n"
            f"  scalar     {scalar:7.2f}s\n"
            f"  vectorized {vector:7.2f}s\n"
            f"  speedup    {speedup:6.1f}x"
        )
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
