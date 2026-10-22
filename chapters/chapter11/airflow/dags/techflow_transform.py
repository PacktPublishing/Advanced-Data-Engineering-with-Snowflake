"""Chapter 11 Airflow 3 DAG: the TechFlow cross-system transform (baseline).

The DAG waits for the fraud team's scores in S3, loads them, runs the cleanse
and the shared Chapter 6 dbt project through Cosmos, rebuilds the day's revenue
rows, and pushes the high-risk segment to the marketing API. This is the
single-DAG baseline from Sections 1.1 to 1.4; the three split DAGs from
Section 1.5 live in fraud_scores_ingest.py, transaction_transform.py, and
marketing_activation.py.

Importing this file defines the DAG and is a real test of the provider
versions: a clean ``python dags/techflow_transform.py`` confirms the imports
resolve. Shared configuration is in techflow_common.py.
"""

from __future__ import annotations

import pendulum
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.sdk import DAG
from airflow.timetables.interval import CronDataIntervalTimetable
from cosmos import DbtTaskGroup
from techflow_common import (
    AWS_CONN_ID,
    DAG_DIR,
    SCORES_BUCKET,
    SNOWFLAKE_CONN_ID,
    build_cosmos_config,
    default_args,
    hook_params,
    push_segment_for_interval,
)

DAG_ID = "techflow_transform"

project_config, profile_config, execution_config, render_config = build_cosmos_config()

with DAG(
    dag_id=DAG_ID,
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    # An explicit data-interval timetable, not a bare cron string: in Airflow 3
    # a plain cron creates runs with no data interval, which collapses {{ ds }}
    # and every date-bounded statement below.
    schedule=CronDataIntervalTimetable("0 2 * * *", timezone="UTC"),
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    template_searchpath=[str(DAG_DIR)],
    tags=["techflow", "snowflake", "dbt"],
) as dag:
    wait_for_scores = S3KeySensor(
        task_id="wait_for_scores",
        bucket_name=SCORES_BUCKET,
        bucket_key="scores/fraud_scores_{{ ds }}.parquet",
        aws_conn_id=AWS_CONN_ID,
        deferrable=True,
        # Deferred, so it holds no worker; it must not hold a Snowflake slot
        # either, since it touches no warehouse.
        pool="default_pool",
    )

    load_scores = SQLExecuteQueryOperator(
        task_id="load_scores",
        conn_id=SNOWFLAKE_CONN_ID,
        sql="sql/load_fraud_scores.sql",
        hook_params=hook_params(DAG_ID, "load_scores", "{{ ds }}"),
    )

    cleanse = SQLExecuteQueryOperator(
        task_id="cleanse_transactions",
        conn_id=SNOWFLAKE_CONN_ID,
        sql="sql/cleanse_transactions.sql",
        hook_params=hook_params(DAG_ID, "cleanse_transactions", "{{ ds }}"),
    )

    dbt_transform = DbtTaskGroup(
        group_id="dbt_transform",
        project_config=project_config,
        profile_config=profile_config,
        execution_config=execution_config,
        render_config=render_config,
        operator_args={"install_deps": False},
    )

    build_daily_revenue = SQLExecuteQueryOperator(
        task_id="build_daily_revenue",
        conn_id=SNOWFLAKE_CONN_ID,
        # The partition-safe write from Section 1.4, not the full-table
        # INSERT OVERWRITE in build_daily_revenue.sql. That file stays in the
        # repo as the teaching artifact the chapter starts from.
        sql="sql/build_daily_revenue_incremental.sql",
        hook_params=hook_params(DAG_ID, "build_daily_revenue", "{{ ds }}"),
        # One BEGIN/DELETE/INSERT/COMMIT block sent as a single multi-statement
        # request, so the transaction is unambiguous. The Snowflake provider
        # supplies num_statements=0 for this from 6.12.2 onward.
        split_statements=False,
        autocommit=False,
    )

    (
        wait_for_scores
        >> load_scores
        >> cleanse
        >> dbt_transform
        >> build_daily_revenue
        >> push_segment_for_interval()
    )


if __name__ == "__main__":
    # Manuscript block 22. Runs the whole DAG in one process against a local
    # metadata database for a fixed partition day. mark_success_pattern marks
    # the sensor successful without evaluating it, so the run never waits on S3.
    # Airflow 3 renamed this argument from execution_date to logical_date.
    dag.test(
        logical_date=pendulum.datetime(2026, 7, 14, tz="UTC"),
        mark_success_pattern="wait_for_scores",
    )
