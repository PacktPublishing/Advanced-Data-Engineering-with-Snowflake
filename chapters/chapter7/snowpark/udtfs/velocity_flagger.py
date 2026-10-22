"""Section 4.1: UDTF that flags rolling-window velocity bursts per customer.

The class encodes the partition contract: ``__init__`` initializes per-
partition state, ``process`` runs once per row and yields zero or more output
rows, ``end_partition`` runs once after the last row. Invoked from Snowpark
with ``partition_by="customer_id"`` and ``order_by="transaction_ts"`` so each
customer's transactions are walked in chronological order.

Run directly to register against your default connection::

    python -m snowpark.udtfs.velocity_flagger
"""

from __future__ import annotations

import sys
from datetime import datetime
from typing import Iterable, Tuple

from snowflake.snowpark import Session
from snowflake.snowpark.functions import udtf
from snowflake.snowpark.types import (
    FloatType,
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from snowpark.session import build_session


class TransactionVelocityFlagger:
    """Emit a VELOCITY_BURST row when a customer trips the rolling threshold."""

    WINDOW_MINUTES = 5
    VELOCITY_THRESHOLD = 5
    AMOUNT_THRESHOLD = 1000.0

    def __init__(self) -> None:
        # Per-partition state, scoped to one customer by partition_by clause.
        self.window: list[Tuple[datetime, float]] = []

    def process(
        self,
        customer_id: str,
        transaction_id: str,
        transaction_ts: datetime,
        amount: float,
    ) -> Iterable[Tuple[str, str, datetime, int, float, str]]:
        cutoff = transaction_ts.timestamp() - (self.WINDOW_MINUTES * 60)
        self.window = [
            (ts, amt) for ts, amt in self.window if ts.timestamp() >= cutoff
        ]
        self.window.append((transaction_ts, amount))

        total_amount = sum(amt for _, amt in self.window)
        if (
            len(self.window) >= self.VELOCITY_THRESHOLD
            and total_amount >= self.AMOUNT_THRESHOLD
        ):
            yield (
                customer_id,
                transaction_id,
                transaction_ts,
                len(self.window),
                float(total_amount),
                "VELOCITY_BURST",
            )

    def end_partition(self) -> Iterable[Tuple]:
        # Hook left in place for future per-partition summaries; nothing to
        # emit today, but keeping the method documents the contract.
        return iter(())


OUTPUT_SCHEMA = StructType(
    [
        StructField("customer_id", StringType()),
        StructField("transaction_id", StringType()),
        StructField("transaction_ts", TimestampType()),
        StructField("window_count", IntegerType()),
        StructField("window_amount", FloatType()),
        StructField("flag_reason", StringType()),
    ]
)


def register(session: Session) -> None:
    """Register ``flag_velocity_bursts`` as a permanent UDTF."""
    udtf(
        TransactionVelocityFlagger,
        output_schema=OUTPUT_SCHEMA,
        name="gold_db.public.flag_velocity_bursts",
        is_permanent=True,
        stage_location="@gold_db.public.udf_stage",
        replace=True,
        session=session,
    )


def main() -> int:
    session = build_session()
    try:
        register(session)
        print("registered flag_velocity_bursts on @gold_db.public.udf_stage")
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
