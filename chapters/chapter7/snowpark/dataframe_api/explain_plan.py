"""Section 1.3: Inspect the generated SQL plan with ``DataFrame.explain``.

Prints the logical plan and rendered SQL Snowpark would send to Snowflake.
Run on a 100-row sample before any DataFrame chain that targets a multi-
billion-row table; a ``LocalRelation`` or Python list constant in the plan
is the early signal that pushdown is broken.

Run with::

    python -m snowpark.dataframe_api.explain_plan
"""

from __future__ import annotations

import sys

from snowpark.dataframe_api.monthly_revenue import build_monthly_revenue
from snowpark.session import build_session


def main() -> int:
    session = build_session()
    try:
        df = build_monthly_revenue(session)
        df.explain()
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
