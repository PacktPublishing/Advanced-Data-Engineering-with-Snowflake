"""Section 2.2: Trigger ``MODIN_DEFAULTING_TO_LOCAL_EXECUTION``.

``DataFrame.corr`` has only partial pushdown support in pandas on Snowflake
and may fall back to local execution. When it does, the engine prints a
``MODIN_DEFAULTING_TO_LOCAL_EXECUTION`` warning naming the operation, which is
the signal we look for in CI. Narrowing the frame with ``head`` first keeps
the fallback cheap.

Run with::

    python -m snowpark.pandas_on_snowflake.fallback_demo
"""

from __future__ import annotations

import logging
import sys

import snowflake.snowpark.modin.plugin  # noqa: F401  -- registers the Snowflake engine with Modin
import modin.pandas as pd  # type: ignore[import-not-found]

from snowpark.session import build_session

# Modin emits the fallback warning via the standard logging module.
logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")


def main() -> int:
    session = build_session()
    try:
        transactions = pd.read_snowflake(
            "GOLD_DB.TRANSACTIONS.FACT_TRANSACTIONS"
        )

        # corr() has only partial pushdown support in pandas on Snowflake and
        # may fall back to local execution; narrowing the frame with head()
        # first keeps it cheap. Watch for MODIN_DEFAULTING_TO_LOCAL_EXECUTION.
        correlation = transactions[["AMOUNT", "RISK_SCORE"]].head(100_000).corr()
        print("corr() (watch for MODIN_DEFAULTING_TO_LOCAL_EXECUTION):")
        print(correlation)
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
