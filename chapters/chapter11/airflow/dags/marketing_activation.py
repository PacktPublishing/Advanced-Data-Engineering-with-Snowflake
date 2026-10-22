"""Chapter 11, Section 1.5: the activation DAG.

Third of the three split DAGs, and the one that shows what partitioned assets
buy. It is scheduled by nothing on a clock: PartitionedAssetTimetable starts a
run only when both upstream assets have an event for the same day, in either
order. IdentityMapper passes the upstream keys through unchanged, so the two
producers' keys must match as literal strings, which is why both set the same
key_format. Importing this file runs nothing.

The deadline alert reports a business signal none of the task-level machinery
can see: the segment is late, whether or not anything failed. Deadline Alerts
are new in Airflow 3.1 and experimental as of August 2026, so expect the API to
move; the pattern of measuring against the business's clock is the durable part.
"""

from __future__ import annotations

from datetime import timedelta

import pendulum
from airflow.providers.slack.notifications.slack_webhook import SlackWebhookNotifier
from airflow.sdk import (
    DAG,
    AsyncCallback,
    DeadlineAlert,
    DeadlineReference,
    IdentityMapper,
    PartitionedAssetTimetable,
)
from techflow_common import (
    FRAUD_SCORES_ASSET,
    REVENUE_ASSET,
    default_args,
    push_segment_for_partition,
)

DAG_ID = "marketing_activation"

with DAG(
    dag_id=DAG_ID,
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    schedule=PartitionedAssetTimetable(
        assets=FRAUD_SCORES_ASSET & REVENUE_ASSET,
        default_partition_mapper=IdentityMapper(),
    ),
    catchup=False,
    default_args=default_args,
    deadline=DeadlineAlert(
        reference=DeadlineReference.DAGRUN_QUEUED_AT,
        interval=timedelta(hours=2),
        callback=AsyncCallback(
            SlackWebhookNotifier,
            kwargs={
                "text": (
                    "Marketing segment for "
                    "{{ dag_run.partition_key }} missed its deadline."
                ),
            },
        ),
    ),
    tags=["techflow", "reverse-etl", "partitioned"],
):
    push_segment_for_partition()
