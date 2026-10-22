"""Chapter 11, Section 1.5: the transform DAG.

Second of the three split DAGs. It owns TechFlow's own data: cleanse, run the
shared Chapter 6 dbt project through Cosmos, rebuild the day's revenue rows,
and emit a partitioned asset event. It carries the identical timetable
arguments as fraud_scores_ingest, because two producers whose partition keys do
not agree can never satisfy one consumer. Importing this file runs nothing.
"""

from __future__ import annotations

import pendulum
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.sdk import DAG, CronPartitionTimetable
from cosmos import DbtTaskGroup
from techflow_common import (
    DAG_DIR,
    REVENUE_ASSET,
    SNOWFLAKE_CONN_ID,
    build_cosmos_config,
    default_args,
    hook_params,
)

DAG_ID = "transaction_transform"
PARTITION = "{{ partition_date | ds }}"

project_config, profile_config, execution_config, render_config = build_cosmos_config()

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
    tags=["techflow", "snowflake", "dbt", "partitioned"],
):
    cleanse = SQLExecuteQueryOperator(
        task_id="cleanse_transactions",
        conn_id=SNOWFLAKE_CONN_ID,
        sql="sql/cleanse_transactions.sql",
        hook_params=hook_params(DAG_ID, "cleanse_transactions", PARTITION),
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
        sql="sql/build_daily_revenue_partitioned.sql",
        hook_params=hook_params(DAG_ID, "build_daily_revenue", PARTITION),
        # The file is one BEGIN/DELETE/INSERT/COMMIT block. Sending it as a
        # single statement keeps the transaction unambiguous; the Snowflake
        # provider supplies num_statements=0 for multi-statement execution
        # (6.12.2 and later).
        split_statements=False,
        autocommit=False,
        outlets=[REVENUE_ASSET],
    )

    cleanse >> dbt_transform >> build_daily_revenue
