"""Chapter 11 Dagster assets for the TechFlow cross-system transform.

Each Snowflake table is an asset; ``deps`` declares the data dependencies and
Dagster derives the run order from them. Every asset is partitioned by day, so
``context.partition_key`` is the same contract the Airflow split DAGs carry as
a partition key and the Prefect flow threads as ``run_date``. Importing this
module defines the assets and the retry policy but executes no SQL and opens no
connection.

Do not add ``from __future__ import annotations`` to this module. Dagster
validates the ``context`` parameter's annotation by comparing the raw value
from ``inspect.signature``, and that import turns every annotation into a
string, so the comparison fails and definition loading raises
DagsterInvalidDefinitionError. Dagster banned the import from its own codebase
for the same reason. Resource parameters are unaffected (those are resolved
with ``get_type_hints``), and sensor modules are unaffected, but keeping the
rule uniform avoids a copy-paste that breaks at load time.
"""

import os
from datetime import date

import dagster as dg
import httpx
from dagster_snowflake import SnowflakeResource

from techflow_orchestration.partitions import DAILY_PARTITIONS
from techflow_orchestration.sql import (
    CLEANSE_SQL,
    COPY_SCORES_SQL,
    DELETE_REVENUE_SQL,
    INSERT_REVENUE_SQL,
    SEGMENT_SQL,
)

MARKETING_URL = os.environ.get(
    "MARKETING_URL", "http://marketing-api:8080/segments"
)

# Dagster does not retry by default; this gives the assets the same two-retry
# hardening as the Airflow and Prefect versions.
RETRIES = dg.RetryPolicy(max_retries=2, delay=30)


def _run_date(context: dg.AssetExecutionContext) -> str:
    """Return the run's partition as a validated ISO date string.

    DailyPartitionsDefinition already produces YYYY-MM-DD, so this is belt and
    braces. It matters for the COPY statement, whose file name is interpolated
    in Python rather than bound as a parameter.
    """
    return date.fromisoformat(context.partition_key).isoformat()


def _tag_session(cursor, context: dg.AssetExecutionContext) -> None:
    """Tag the session so Snowflake cost groups by asset and partition.

    The tag has to ride the same session as the DML, which is why it is issued
    on this cursor rather than in a separate task.
    """
    cursor.execute(
        "ALTER SESSION SET QUERY_TAG = %(tag)s",
        {
            "tag": (
                f"dagster:{context.asset_key.to_user_string()}"
                f":{context.partition_key}"
            )
        },
    )


@dg.asset(
    group_name="raw",
    partitions_def=DAILY_PARTITIONS,
    retry_policy=RETRIES,
    kinds={"snowflake", "sql"},
)
def fraud_scores(
    context: dg.AssetExecutionContext, snowflake: SnowflakeResource
) -> None:
    """Load the partition's scores file into the landing table."""
    run_date = _run_date(context)
    with snowflake.get_connection() as connection:
        cursor = connection.cursor()
        _tag_session(cursor, context)
        cursor.execute(COPY_SCORES_SQL.format(run_date=run_date))


@dg.asset(
    group_name="silver",
    partitions_def=DAILY_PARTITIONS,
    retry_policy=RETRIES,
    kinds={"snowflake", "sql"},
)
def transactions_clean(
    context: dg.AssetExecutionContext, snowflake: SnowflakeResource
) -> None:
    """Cleanse raw transactions into the silver transaction table.

    The Chapter 9 procedure is stream-driven, so it processes whatever is
    pending rather than a named day. It is safe to rerun, but it cannot
    reconstruct a past day, which is the same honest limit the chapter states
    for the Airflow replay drill.
    """
    with snowflake.get_connection() as connection:
        cursor = connection.cursor()
        _tag_session(cursor, context)
        cursor.execute(CLEANSE_SQL)


@dg.asset(
    group_name="gold",
    partitions_def=DAILY_PARTITIONS,
    # The dbt dependency is declared, not assumed. Dagster orders only what you
    # declare: without this key the aggregate would materialize beside the dbt
    # models instead of after them, and a run where dbt failed could still push
    # a segment built on stale numbers.
    deps=[transactions_clean, dg.AssetKey("merchant_activity")],
    retry_policy=RETRIES,
    kinds={"snowflake", "sql"},
)
def merchant_daily_revenue(
    context: dg.AssetExecutionContext, snowflake: SnowflakeResource
) -> None:
    """Rebuild the partition's completed-revenue rows by merchant.

    The DELETE and the INSERT run as separate statements inside one explicit
    transaction on one session, so a failure cannot leave the day half-written.
    Snowflake keeps an explicit transaction open across separate execute calls
    on the same session, and AUTOCOMMIT does not apply inside one.
    """
    run_date = _run_date(context)
    with snowflake.get_connection() as connection:
        cursor = connection.cursor()
        _tag_session(cursor, context)
        cursor.execute("BEGIN")
        try:
            cursor.execute(DELETE_REVENUE_SQL, {"run_date": run_date})
            cursor.execute(INSERT_REVENUE_SQL, {"run_date": run_date})
        except Exception:
            cursor.execute("ROLLBACK")
            raise
        cursor.execute("COMMIT")


@dg.asset(
    group_name="reverse_etl",
    partitions_def=DAILY_PARTITIONS,
    deps=[merchant_daily_revenue, fraud_scores],
    retry_policy=RETRIES,
    kinds={"snowflake", "python"},
)
def marketing_segment(
    context: dg.AssetExecutionContext, snowflake: SnowflakeResource
) -> None:
    """Query the partition's high-risk segment and POST it to the marketing API."""
    run_date = _run_date(context)
    with snowflake.get_connection() as connection:
        cursor = connection.cursor()
        _tag_session(cursor, context)
        rows = cursor.execute(SEGMENT_SQL, {"run_date": run_date}).fetchall()

    # Snowflake returns NUMBER columns as Decimal, which the JSON encoder
    # cannot serialize; float() matches what the Airflow and Prefect pushes do.
    segment = [
        {
            "merchant_id": merchant_id,
            "revenue": float(revenue),
            "risk": float(risk),
        }
        for merchant_id, revenue, risk in rows
    ]

    # The key is the partition, not the run id: a rematerialization of the same
    # day must present the same key so the marketing tool deduplicates it. A
    # run id would change on every attempt and defeat the whole contract.
    response = httpx.post(
        MARKETING_URL,
        json=segment,
        headers={"Idempotency-Key": f"techflow-{run_date}"},
        timeout=30,
    )
    response.raise_for_status()
