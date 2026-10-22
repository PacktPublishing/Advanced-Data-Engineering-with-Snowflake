"""Daily partition definition shared by the Chapter 11 Dagster assets.

Partitions are a first-class dimension of an asset in Dagster, not something
bolted on by a timetable: every partition carries its own materialization state
in the UI, and a backfill selects partitions directly. The sensor stamps each
run request with the day it parsed out of the incoming file's name, so the
whole graph materializes for one day at a time, matching what the Airflow split
DAGs express with partition keys and what the Prefect flow threads by hand.

Importing this module defines the partition set and nothing else.
"""

import re

import dagster as dg

# Matches fraud_scores_2026-07-14.parquet and captures the date.
SCORES_KEY_PATTERN = re.compile(r"fraud_scores_(\d{4}-\d{2}-\d{2})\.parquet$")

DAILY_PARTITIONS = dg.DailyPartitionsDefinition(
    start_date="2026-01-01",
    timezone="UTC",
)


def partition_key_from_object_key(object_key: str) -> str | None:
    """Return the partition date encoded in a scores file name, if any.

    A file the sensor cannot place on the calendar is skipped rather than
    guessed at, because materializing the wrong partition is worse than
    materializing none.
    """
    match = SCORES_KEY_PATTERN.search(object_key)
    return match.group(1) if match else None
