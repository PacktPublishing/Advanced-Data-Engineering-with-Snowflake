"""Section 3.2: Vectorized UDF that runs once per batch of rows.

A vectorized UDF receives a ``pandas.Series`` per input column and returns a
``pandas.Series`` of results. Batching amortizes the per-invocation Python
overhead across thousands of rows, but it is not an automatic win: for cheap
row-wise rules like this one the per-batch cost (building string arrays,
copying Series) can outweigh the savings, so the scalar variant is often
faster here. Vectorization pays off when the per-row Python work is expensive
(model inference, regex, JSON parsing). Benchmark your own handler before
committing to the rewrite -- see ``benchmark_udfs.py``.

Run directly to register against your default connection::

    python -m snowpark.udfs.vectorized_risk_tier
"""

from __future__ import annotations

import sys

import numpy as np
import pandas as pd
from snowflake.snowpark import Session
from snowflake.snowpark.functions import pandas_udf
from snowflake.snowpark.types import (
    FloatType,
    PandasSeriesType,
    StringType,
)

from snowpark.session import build_session


def classify_risk_tier_vec_logic(
    risk_score: pd.Series,
    amount: pd.Series,
) -> pd.Series:
    """Pure-pandas implementation, callable from unit tests without Snowflake."""
    score = risk_score.fillna(0)
    amt = amount.fillna(0)
    conditions = [
        (score >= 80) | (amt > 5000),
        (score >= 50) | (amt > 1000),
    ]
    choices = ["HIGH", "MEDIUM"]
    out = pd.Series(np.select(conditions, choices, default="LOW"))
    # Match the scalar UDF: if either input is NULL, the tier is UNKNOWN.
    unknown = risk_score.isna() | amount.isna()
    out[unknown.values] = "UNKNOWN"
    return out


def register(session: Session) -> None:
    """Register ``classify_risk_tier_vec`` as a permanent vectorized UDF."""

    @pandas_udf(
        name="gold_db.public.classify_risk_tier_vec",
        is_permanent=True,
        stage_location="@gold_db.public.udf_stage",
        replace=True,
        return_type=PandasSeriesType(StringType()),
        input_types=[PandasSeriesType(FloatType()), PandasSeriesType(FloatType())],
        session=session,
    )
    def classify_risk_tier_vec(
        risk_score: pd.Series,
        amount: pd.Series,
    ) -> pd.Series:
        score = risk_score.fillna(0)
        amt = amount.fillna(0)
        conditions = [
            (score >= 80) | (amt > 5000),
            (score >= 50) | (amt > 1000),
        ]
        choices = ["HIGH", "MEDIUM"]
        out = pd.Series(np.select(conditions, choices, default="LOW"))
        # Match the scalar UDF: if either input is NULL, the tier is UNKNOWN.
        unknown = risk_score.isna() | amount.isna()
        out[unknown.values] = "UNKNOWN"
        return out

    _ = classify_risk_tier_vec


def main() -> int:
    session = build_session()
    try:
        register(session)
        print("registered classify_risk_tier_vec on @gold_db.public.udf_stage")
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
