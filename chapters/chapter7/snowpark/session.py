"""Reusable Snowpark session builder for chapter 7.

Every script in this folder calls :func:`build_session` so the chapter has one
place to change the connection profile, warehouse, or database defaults.

The connection name resolves to ``~/.snowflake/config.toml``: see
``config.toml.example`` next to this folder for the expected entry shape.

Run directly as ``python -m snowpark.session`` to smoke-test the connection.
"""

from __future__ import annotations

import os
import sys
from typing import Optional

from snowflake.snowpark import Session


def build_session(
    connection_name: Optional[str] = None,
    database: str = "GOLD_DB",
    schema: str = "TRANSACTIONS",
    warehouse: str = "BOOK_WH",
) -> Session:
    """Build a Snowpark Session pinned to the chapter defaults.

    Parameters
    ----------
    connection_name:
        Profile name in ``~/.snowflake/config.toml``. Falls back to the
        ``SNOWFLAKE_CONNECTION_NAME`` env var, then to ``"default"``.
    database, schema, warehouse:
        Active context applied after the session is created so the example
        scripts can reference unqualified object names.
    """
    name = (
        connection_name
        or os.environ.get("SNOWFLAKE_CONNECTION_NAME")
        or "default"
    )
    session = Session.builder.config("connection_name", name).create()
    session.use_database(database)
    session.use_schema(schema)
    session.use_warehouse(warehouse)
    return session


def main() -> int:
    session = build_session()
    try:
        ctx = session.sql(
            "SELECT CURRENT_ACCOUNT() AS account, "
            "CURRENT_ROLE() AS role, "
            "CURRENT_WAREHOUSE() AS warehouse, "
            "CURRENT_DATABASE() AS database, "
            "CURRENT_SCHEMA() AS schema"
        ).collect()[0]
        print(
            f"account={ctx['ACCOUNT']} role={ctx['ROLE']} "
            f"wh={ctx['WAREHOUSE']} db={ctx['DATABASE']} "
            f"schema={ctx['SCHEMA']} OK"
        )
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
