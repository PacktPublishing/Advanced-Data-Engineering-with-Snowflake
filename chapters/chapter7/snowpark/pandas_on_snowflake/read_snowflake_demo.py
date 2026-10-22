"""Section 2.1: Read a Snowflake table as a Modin pandas DataFrame.

``pd.read_snowflake`` returns a Modin frame backed by a deferred query. The
operations we chain (boolean indexing, ``dt.year`` / ``dt.month``,
``groupby().sum()``) push down into the same SQL Snowflake executes.
``head(10)`` is the terminal action that materializes ten rows.

Pandas on Snowflake does not support the ``Period`` dtype, so ``dt.to_period``
is unavailable; group by year and month columns instead.

Run with::

    python -m snowpark.pandas_on_snowflake.read_snowflake_demo
"""

from __future__ import annotations

import sys

import snowflake.snowpark.modin.plugin  # noqa: F401  -- registers the Snowflake engine with Modin
import modin.pandas as pd  # type: ignore[import-not-found]

from snowpark.session import build_session


def main() -> int:
    # The session is created so Modin can discover the connection context
    # without us passing it explicitly to read_snowflake.
    session = build_session()
    try:
        transactions = pd.read_snowflake(
            "GOLD_DB.TRANSACTIONS.FACT_TRANSACTIONS"
        )

        completed = transactions[transactions["STATUS"] == "COMPLETED"].copy()
        completed["REVENUE_YEAR"] = completed["TRANSACTION_TS"].dt.year
        completed["REVENUE_MONTH"] = completed["TRANSACTION_TS"].dt.month

        monthly = (
            completed.groupby(
                ["MERCHANT_ID", "REVENUE_YEAR", "REVENUE_MONTH"]
            )["AMOUNT"]
            .sum()
            .reset_index(name="MONTHLY_REVENUE")
            .sort_values(["MERCHANT_ID", "REVENUE_YEAR", "REVENUE_MONTH"])
        )

        print(monthly.head(10))
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
