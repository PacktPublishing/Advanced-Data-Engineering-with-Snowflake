"""Section 5.3: Warehouse-backed smoke tests run in CI's integration job.

These tests are skipped unless ``SNOWFLAKE_CONNECTION_NAME`` is set, so the
local unit suite stays free. The integration job in
``ci/github-actions-snowpark.yml`` populates the env var from CI secrets.
"""

from __future__ import annotations

import os
import uuid

import pytest

CONNECTION = os.environ.get("SNOWFLAKE_CONNECTION_NAME")

pytestmark = pytest.mark.skipif(
    CONNECTION is None,
    reason="SNOWFLAKE_CONNECTION_NAME is unset; integration tests are opt-in.",
)


@pytest.fixture(scope="module")
def warehouse_session():
    from snowpark.session import build_session

    session = build_session(connection_name=CONNECTION)
    try:
        yield session
    finally:
        session.close()


def test_classify_risk_tier_against_warehouse(warehouse_session):
    """Round-trip the scalar UDF through Snowflake on a 3-row sample."""
    rows = warehouse_session.sql(
        """
        SELECT classify_risk_tier(90.0::FLOAT, 100.0::FLOAT) AS high_tier,
               classify_risk_tier(60.0::FLOAT, 100.0::FLOAT) AS medium_tier,
               classify_risk_tier(10.0::FLOAT, 100.0::FLOAT) AS low_tier
        """
    ).collect()
    assert rows[0]["HIGH_TIER"] == "HIGH"
    assert rows[0]["MEDIUM_TIER"] == "MEDIUM"
    assert rows[0]["LOW_TIER"] == "LOW"


def test_promote_customer_batch_empty(warehouse_session):
    """A batch_id that does not exist should produce an EMPTY status row."""
    batch = f"smoke-{uuid.uuid4()}"
    result = warehouse_session.sql(
        "CALL gold_db.public.promote_customer_batch(?)",
        params=[batch],
    ).collect()
    assert result[0][0] == "EMPTY"

    audit = warehouse_session.sql(
        "SELECT status FROM gold_db.control.batch_log "
        "WHERE batch_id = ? ORDER BY logged_at DESC LIMIT 1",
        params=[batch],
    ).collect()
    assert audit[0]["STATUS"] == "EMPTY"
