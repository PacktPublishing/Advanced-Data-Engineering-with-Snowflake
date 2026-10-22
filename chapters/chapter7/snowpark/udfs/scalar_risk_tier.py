"""Section 3.1: Scalar UDF that classifies a transaction into a risk tier.

The function logic is kept as a plain Python function so the unit tests in
``tests/unit/test_udfs.py`` can exercise every branch without registering the
UDF anywhere. :func:`register` performs the Snowflake registration when
``commands/deploy_udfs.sh`` runs.

Run directly to register against your default connection::

    python -m snowpark.udfs.scalar_risk_tier
"""

from __future__ import annotations

import sys
from typing import Optional

from snowflake.snowpark import Session
from snowflake.snowpark.functions import udf
from snowflake.snowpark.types import FloatType, StringType

from snowpark.session import build_session


def classify_risk_tier_logic(
    risk_score: Optional[float],
    amount: Optional[float],
) -> str:
    """Pure-Python implementation of the chapter's risk-tier rule."""
    if risk_score is None or amount is None:
        return "UNKNOWN"
    if risk_score >= 80 or amount > 5000:
        return "HIGH"
    if risk_score >= 50 or amount > 1000:
        return "MEDIUM"
    return "LOW"


def register(session: Session) -> None:
    """Register ``classify_risk_tier`` as a permanent scalar UDF."""

    @udf(
        name="gold_db.public.classify_risk_tier",
        is_permanent=True,
        stage_location="@gold_db.public.udf_stage",
        replace=True,
        return_type=StringType(),
        input_types=[FloatType(), FloatType()],
        session=session,
    )
    def classify_risk_tier(risk_score: float, amount: float) -> str:
        # Re-implement the body here so Snowpark serializes a self-contained
        # closure without the local-import dependency on this module.
        if risk_score is None or amount is None:
            return "UNKNOWN"
        if risk_score >= 80 or amount > 5000:
            return "HIGH"
        if risk_score >= 50 or amount > 1000:
            return "MEDIUM"
        return "LOW"

    _ = classify_risk_tier  # silence "unused" linters; the decorator does the work


def main() -> int:
    session = build_session()
    try:
        register(session)
        print("registered classify_risk_tier on @gold_db.public.udf_stage")
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
