"""Section 4.1 / 5.1: UDTF unit test against the local engine.

We instantiate ``TransactionVelocityFlagger`` directly because the chapter's
boundary rules sit in plain Python state, and the test reads cleaner than
constructing partitioned DataFrames for every case.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from snowpark.udtfs.velocity_flagger import TransactionVelocityFlagger


def _drive(flagger, events):
    rows = []
    for event in events:
        rows.extend(list(flagger.process(*event)))
    rows.extend(list(flagger.end_partition()))
    return rows


def test_velocity_burst_fires_after_threshold():
    flagger = TransactionVelocityFlagger()
    base = datetime(2026, 4, 29, 12, 0, 0)
    events = [
        ("C1", "T1", base + timedelta(seconds=10), 200.0),
        ("C1", "T2", base + timedelta(seconds=20), 200.0),
        ("C1", "T3", base + timedelta(seconds=30), 200.0),
        ("C1", "T4", base + timedelta(seconds=40), 200.0),
        ("C1", "T5", base + timedelta(seconds=50), 200.0),
    ]
    rows = _drive(flagger, events)

    assert len(rows) == 1
    row = rows[0]
    assert row[0] == "C1"
    assert row[1] == "T5"
    assert row[3] == 5
    assert row[4] == 1000.0
    assert row[5] == "VELOCITY_BURST"


def test_old_events_evicted_from_window():
    flagger = TransactionVelocityFlagger()
    base = datetime(2026, 4, 29, 12, 0, 0)
    events = [
        ("C1", "T1", base, 500.0),
        # 10 minutes later: the first event has aged out of the window.
        ("C1", "T2", base + timedelta(minutes=10), 200.0),
    ]
    rows = _drive(flagger, events)
    assert rows == []
