"""Shared configuration for the Chapter 11 Airflow DAGs.

The baseline DAG (``techflow_transform``) and the three split DAGs from the
*Splitting at Durable Asset Boundaries* section import everything here, so the
connection ids, the pool, the Cosmos configuration, and the reverse-ETL task
are defined once. Importing this module builds configuration objects only; it
opens no connection and runs no SQL.
"""

from __future__ import annotations

from pathlib import Path

import pendulum
import requests
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from airflow.sdk import Asset, task
from cosmos import (
    ExecutionConfig,
    ExecutionMode,
    LoadMode,
    ProfileConfig,
    ProjectConfig,
    RenderConfig,
)
from cosmos.profiles import SnowflakePrivateKeyPemProfileMapping

CHAPTER_DIR = Path(__file__).resolve().parents[2]
DAG_DIR = CHAPTER_DIR / "airflow" / "dags"
# One shared dbt project lives in Chapter 6; there is no chapter-11 copy. The
# path is derived from this file's location so it loads in any environment.
DBT_PROJECT_DIR = CHAPTER_DIR.parent / "chapter6" / "dbt" / "techflow_warehouse"
DBT_MANIFEST_PATH = CHAPTER_DIR / "airflow" / "manifests" / "manifest.json"

SNOWFLAKE_CONN_ID = "snowflake_techflow"
AWS_CONN_ID = "aws_techflow"
WAREHOUSE = "BOOK_WH"
# Every Snowflake-touching task claims a slot in this pool, so the orchestrator
# cannot queue more concurrent statements against BOOK_WH than the warehouse
# runs comfortably, no matter how many runs or backfills are active. Create it
# once with airflow/init_pools.sh.
SNOWFLAKE_POOL = "snowflake_book_wh"
SCORES_BUCKET = "techflow-ml"
MARKETING_URL = "http://marketing-api:8080/segments"

# Both sides are scoped to the run's day. Without the scored_date predicate the
# join fans out: fraud_scores keeps one row per merchant per scored day, so after
# a week every high-risk merchant would appear seven times in the pushed segment.
SEGMENT_SQL = """
    SELECT r.merchant_id, r.gross_revenue, s.risk_score
    FROM gold_db.transactions.merchant_daily_revenue r
    JOIN raw_db.streaming.fraud_scores s USING (merchant_id)
    WHERE s.risk_score > 0.8
      AND r.revenue_date = TO_DATE(%(run_date)s)
      AND s.scored_date = TO_DATE(%(run_date)s)
"""

# Assets are the contract between the split DAGs: a producer stamps an event
# with the day it just wrote, and the consumer waits for matching days.
# The Snowflake provider sanitizes this scheme: netloc is the account
# identifier (lineage, not a credential) and the path must be
# /database/schema/table. snowflake://raw_db/streaming/fraud_scores fails
# import with "must contain database, schema, and table names".
FRAUD_SCORES_ASSET = Asset(
    uri="snowflake://book/raw_db/streaming/fraud_scores",
    name="fraud_scores",
)
REVENUE_ASSET = Asset(
    uri="snowflake://book/gold_db/transactions/merchant_daily_revenue",
    name="merchant_daily_revenue",
)

default_args = {
    "owner": "data-platform",
    "retries": 2,
    "retry_delay": pendulum.duration(minutes=5),
    "retry_exponential_backoff": True,
    "execution_timeout": pendulum.duration(hours=1),
    "pool": SNOWFLAKE_POOL,
}


def hook_params(dag_id: str, task_id: str, partition: str) -> dict[str, object]:
    """Session settings that pin the warehouse and tag queries for cost.

    The tag carries the DAG, the task, and the partition, so the cost query in
    the *Releasing and Tracing Every Run* section can group spend by pipeline
    step and by day. Setting it through session_parameters puts the tag on the
    same session as the DML; a separate ALTER SESSION task would not.
    """
    return {
        "warehouse": WAREHOUSE,
        "session_parameters": {
            "QUERY_TAG": f"airflow:{dag_id}:{task_id}:{partition}",
        },
    }


def build_cosmos_config() -> tuple[ProjectConfig, ProfileConfig, ExecutionConfig, RenderConfig]:
    """Cosmos configuration for the shared Chapter 6 dbt project."""
    profile_config = ProfileConfig(
        profile_name="techflow_warehouse",
        target_name="prod",
        profile_mapping=SnowflakePrivateKeyPemProfileMapping(
            conn_id=SNOWFLAKE_CONN_ID,
            profile_args={
                "database": "GOLD_DB",
                "schema": "TRANSACTIONS",
                "warehouse": WAREHOUSE,
                "role": "TRANSFORMER_RL",
            },
        ),
    )
    # Point ProjectConfig at a pre-built manifest so DAG parsing reads the
    # compiled graph without shelling out to dbt on every parse.
    project_config = ProjectConfig(
        manifest_path=DBT_MANIFEST_PATH,
        project_name="techflow_warehouse",
        install_dbt_deps=False,
    )
    execution_config = ExecutionConfig(
        execution_mode=ExecutionMode.LOCAL,
        dbt_project_path=DBT_PROJECT_DIR,
    )
    render_config = RenderConfig(
        load_method=LoadMode.DBT_MANIFEST,
        select=["tag:nightly"],
    )
    return project_config, profile_config, execution_config, render_config


def _post_segment(run_date: str) -> None:
    """Query the day's high-risk segment and POST it to the marketing API.

    The date is bound as a query parameter, and the idempotency key derived
    from it lets the marketing tool deduplicate a retried POST. Snowflake
    returns NUMBER columns as Decimal, which the JSON encoder cannot serialize,
    so both values are converted to float before the request.
    """
    hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID, warehouse=WAREHOUSE)
    rows = hook.get_records(SEGMENT_SQL, parameters={"run_date": run_date})
    segment = [
        {"merchant_id": merchant_id, "revenue": float(revenue), "risk": float(risk)}
        for merchant_id, revenue, risk in rows
    ]
    response = requests.post(
        MARKETING_URL,
        json=segment,
        headers={"Idempotency-Key": f"techflow-{run_date}"},
        timeout=30,
    )
    response.raise_for_status()


@task(pool=SNOWFLAKE_POOL)
def push_segment_for_interval(ds: str | None = None) -> None:
    """Reverse ETL for the baseline DAG, which owns a data interval."""
    _post_segment(ds)


@task(pool=SNOWFLAKE_POOL)
def push_segment_for_partition(dag_run=None) -> None:
    """Reverse ETL for the partitioned activation DAG.

    A partitioned run carries its day on the DagRun rather than in ``ds``.
    Manual runs triggered without a key are unpartitioned, so this fails loudly
    instead of silently pushing the wrong day.
    """
    partition_key = getattr(dag_run, "partition_key", None)
    if not partition_key:
        raise ValueError(
            "marketing_activation requires a partitioned run; trigger it with a "
            "partition_key or let the asset timetable schedule it"
        )
    _post_segment(partition_key)
