"""Section 5.1: Pytest fixtures for the local Snowpark engine.

The ``local_session`` fixture spins up an in-memory Snowpark session that
exercises the same DataFrame plan as a remote session, without any network
round-trip or warehouse credits. Promote the scope to ``module`` or
``session`` for larger suites if the per-test setup cost dominates.
"""

from __future__ import annotations

import pytest
from snowflake.snowpark import Session


@pytest.fixture(scope="function")
def local_session():
    session = Session.builder.config("local_testing", True).create()
    try:
        yield session
    finally:
        session.close()
