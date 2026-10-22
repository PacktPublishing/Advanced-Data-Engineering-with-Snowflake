"""Section 5.2: UDF unit tests against the local Snowpark engine.

The pure-Python ``classify_risk_tier_logic`` and the pandas-Series
``classify_risk_tier_vec_logic`` are exercised directly so every branch and
boundary is covered without ever serializing the function to Snowflake.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from snowpark.udfs.scalar_risk_tier import classify_risk_tier_logic
from snowpark.udfs.vectorized_risk_tier import classify_risk_tier_vec_logic


@pytest.mark.parametrize(
    "risk_score, amount, expected",
    [
        (None, 100.0, "UNKNOWN"),
        (10.0, None, "UNKNOWN"),
        (10.0, 100.0, "LOW"),
        (60.0, 100.0, "MEDIUM"),
        (40.0, 1500.0, "MEDIUM"),
        (90.0, 100.0, "HIGH"),
        (40.0, 6000.0, "HIGH"),
        (80.0, 5000.01, "HIGH"),
    ],
)
def test_scalar_risk_tier_boundaries(risk_score, amount, expected):
    assert classify_risk_tier_logic(risk_score, amount) == expected


def test_vectorized_matches_scalar_on_batch():
    # A NaN in either column appears in both series so the test pins the
    # UNKNOWN branch the chapter aligned with the scalar UDF.
    score = pd.Series([np.nan, 10.0, 60.0, 40.0, 90.0, 40.0, 80.0])
    amount = pd.Series([100.0, 100.0, 100.0, 1500.0, np.nan, 6000.0, 5000.01])

    vectorized = classify_risk_tier_vec_logic(score, amount)
    scalar = pd.Series(
        [
            classify_risk_tier_logic(
                None if pd.isna(s) else float(s),
                None if pd.isna(a) else float(a),
            )
            for s, a in zip(score, amount)
        ]
    )

    # The vectorized UDF now mirrors the scalar rule exactly: UNKNOWN whenever
    # either input is NULL, so the two series match element for element.
    pd.testing.assert_series_equal(
        vectorized.reset_index(drop=True),
        scalar.reset_index(drop=True),
    )


def test_vectorized_returns_pandas_series():
    score = pd.Series([90.0, 10.0])
    amount = pd.Series([100.0, 100.0])
    out = classify_risk_tier_vec_logic(score, amount)
    assert isinstance(out, pd.Series)
    assert out.tolist() == ["HIGH", "LOW"]
