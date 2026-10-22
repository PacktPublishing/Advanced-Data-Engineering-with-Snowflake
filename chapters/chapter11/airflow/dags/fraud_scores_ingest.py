"""Chapter 11, Section 1.5: the score-ingest DAG.

First of the three split DAGs. It owns the boundary with the fraud team: wait
for the day's scores file in S3, COPY it into the landing table, and emit a
partitioned asset event so the downstream DAGs know that day's data is in
Snowflake. Importing this file defines the DAG and runs nothing.

Watch the timetable arguments. ``key_format`` defaults to a full timestamp, so
a bare CronPartitionTimetable would stamp 2026-07-15T02:00:00 rather than a
date, and the templated filename below would look for a file that never exists.
``run_offset=-1`` moves the key one cron tick back, so the 02:00 run owns the
previous day, which is the day its data covers.
"""

from __future__ import annotations

import pendulum
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.sdk import DAG, CronPartitionTimetable
from techflow_common import (
    AWS_CONN_ID,
    DAG_DIR,
    FRAUD_SCORES_ASSET,
    SCORES_BUCKET,
    SNOWFLAKE_CONN_ID,
    default_args,
    hook_params,
)

DAG_ID = "fraud_scores_ingest"

with DAG(
    dag_id=DAG_ID,
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    schedule=CronPartitionTimetable(
        "0 2 * * *",
        timezone="UTC",
        run_offset=-1,
        key_format="%Y-%m-%d",
    ),
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    template_searchpath=[str(DAG_DIR)],
    tags=["techflow", "snowflake", "partitioned"],
):
    wait_for_scores = S3KeySensor(
        task_id="wait_for_scores",
        bucket_name=SCORES_BUCKET,
        bucket_key="scores/fraud_scores_{{ partition_date | ds }}.parquet",
        aws_conn_id=AWS_CONN_ID,
        deferrable=True,
        # A deferred sensor releases its worker slot, so it must not hold a
        # Snowflake pool slot either; it touches no warehouse.
        pool="default_pool",
    )

    load_scores = SQLExecuteQueryOperator(
        task_id="load_scores",
        conn_id=SNOWFLAKE_CONN_ID,
        sql="sql/load_fraud_scores_partitioned.sql",
        hook_params=hook_params(
            DAG_ID, "load_scores", "{{ partition_date | ds }}"
        ),
        # The event is emitted when this task succeeds, so the downstream
        # signal means the data is in the table, not merely that a run finished.
        outlets=[FRAUD_SCORES_ASSET],
    )

    wait_for_scores >> load_scores
