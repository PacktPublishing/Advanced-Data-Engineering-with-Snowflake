"""Section 4.2: Stored procedure that promotes a staged customer batch.

The procedure runs entirely inside Snowflake's compute. It validates the
staged rows, branches on the validation result, and either MERGEs into
``gold_db.customers.dim_customers`` or writes an INVALID/EMPTY row to
``gold_db.control.batch_log``. Every SQL call uses bind variables so user
input never lands in concatenated SQL.

Run directly to register against your default connection::

    python -m snowpark.sprocs.promote_customer_batch
"""

from __future__ import annotations

import sys

from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, sproc

from snowpark.session import build_session


def register(session: Session) -> None:
    """Register ``promote_customer_batch`` as a permanent stored procedure."""

    @sproc(
        name="gold_db.public.promote_customer_batch",
        is_permanent=True,
        stage_location="@gold_db.public.sproc_stage",
        replace=True,
        packages=["snowflake-snowpark-python"],
        session=session,
    )
    def promote_customer_batch(session: Session, batch_id: str) -> str:
        staging_count = (
            session.table("gold_db.staging.customer_batch")
            .filter(col("batch_id") == batch_id)
            .count()
        )
        if staging_count == 0:
            session.sql(
                "INSERT INTO gold_db.control.batch_log "
                "VALUES (?, 'EMPTY', CURRENT_TIMESTAMP())",
                params=[batch_id],
            ).collect()
            return "EMPTY"

        bad_rows = (
            session.table("gold_db.staging.customer_batch")
            .filter(
                (col("batch_id") == batch_id) & (col("customer_id").is_null())
            )
            .count()
        )
        if bad_rows > 0:
            session.sql(
                "INSERT INTO gold_db.control.batch_log "
                "VALUES (?, 'INVALID', CURRENT_TIMESTAMP())",
                params=[batch_id],
            ).collect()
            return f"INVALID: {bad_rows} rows missing customer_id"

        session.sql(
            """
            MERGE INTO gold_db.customers.dim_customers tgt
            USING (
                SELECT customer_id, customer_name, email, address_line1,
                       city, state, postal_code
                FROM gold_db.staging.customer_batch
                WHERE batch_id = ?
            ) src
            ON tgt.customer_id = src.customer_id AND tgt.is_current = TRUE
            WHEN MATCHED THEN UPDATE SET
                tgt.customer_name = src.customer_name,
                tgt.email         = src.email
            WHEN NOT MATCHED THEN INSERT
                (customer_id, customer_name, email, address_line1,
                 city, state, postal_code, effective_from, is_current)
            VALUES
                (src.customer_id, src.customer_name, src.email,
                 src.address_line1, src.city, src.state,
                 src.postal_code, CURRENT_TIMESTAMP(), TRUE)
            """,
            params=[batch_id],
        ).collect()

        session.sql(
            "INSERT INTO gold_db.control.batch_log "
            "VALUES (?, 'PROMOTED', CURRENT_TIMESTAMP())",
            params=[batch_id],
        ).collect()

        return "PROMOTED"

    _ = promote_customer_batch


def main() -> int:
    session = build_session()
    try:
        register(session)
        print(
            "registered promote_customer_batch on @gold_db.public.sproc_stage"
        )
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
