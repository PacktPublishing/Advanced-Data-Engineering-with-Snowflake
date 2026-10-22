"""Chapter 11 Prefect flow: the TechFlow cross-system transform.

Prefect has no sensor in this sample, so the wait is a task that checks S3 once
and lets the retry policy poll. Each SQL task loads its connector block, runs
one trusted statement in an explicit transaction, and commits. Importing this
module defines the tasks and flow but connects to nothing.

The partition contract has no primitive here: it lives in the validated
``run_date`` parameter and is threaded by hand into the load, the aggregate,
and the push. Nothing in Prefect enforces that those steps mean the same day,
which is the honest cost of the model.
"""

from __future__ import annotations

import os
import re
from datetime import date, timedelta, timezone
from pathlib import Path

import boto3
import httpx
from botocore.exceptions import ClientError
from prefect import flow, task
from prefect.runtime import flow_run
from prefect_dbt import PrefectDbtRunner, PrefectDbtSettings
from prefect_snowflake.database import SnowflakeConnector
from snowflake.connector.errors import Error as SnowflakeError

BLOCK_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,127}$")

SCORES_BUCKET = "techflow-ml"
MARKETING_URL = os.environ.get(
    "MARKETING_URL", "http://marketing-api:8080/segments"
)

# One shared dbt project lives in Chapter 6; there is no chapter-11 copy. Pin
# the runner to it so the flow runs from any working directory and a wrong path
# fails immediately with a project-not-found error.
DBT_PROJECT_DIR = (
    Path(__file__).resolve().parents[2] / "chapter6" / "dbt" / "techflow_warehouse"
)

CLEANSE_SQL = "CALL ops_db.pipelines.run_cleanse()"

# Every statement binds the run's day. run_date is validated as a real ISO date
# before it reaches any of them, so no unbound flow input touches the SQL.
COPY_SCORES_SQL = """
COPY INTO raw_db.streaming.fraud_scores
FROM @raw_db.streaming.ml_scores_stage
FILES = ('fraud_scores_{run_date}.parquet')
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
"""

# The partition-scoped rebuild is two statements, run inside one transaction by
# rebuild_revenue_partition below. They are separate constants because the
# Snowflake connector executes one statement per call unless multi-statement
# execution is enabled explicitly, and because keeping them apart lets the date
# bind as a query parameter instead of being formatted into the string.
DELETE_REVENUE_SQL = """
DELETE FROM gold_db.transactions.merchant_daily_revenue
WHERE revenue_date = TO_DATE(%(run_date)s)
"""

INSERT_REVENUE_SQL = """
INSERT INTO gold_db.transactions.merchant_daily_revenue
SELECT merchant_id, DATE_TRUNC('day', transaction_ts) AS revenue_date,
       COUNT(*) AS transaction_count, SUM(amount) AS gross_revenue
FROM silver_db.transactions.transactions_clean
WHERE status = 'COMPLETED'
  AND DATE_TRUNC('day', transaction_ts) = TO_DATE(%(run_date)s)
GROUP BY 1, 2
"""

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


def _validate_block_name(block_name: str) -> None:
    """Reject malformed Prefect block names before a server lookup."""
    if BLOCK_NAME_PATTERN.fullmatch(block_name) is None:
        raise ValueError(
            "block_name must contain only lowercase letters, numbers, and hyphens"
        )


def _resolve_run_date(run_date: str | None) -> str:
    """Return the day this run owns, as an ISO date string.

    A passed-in value is validated as a real date before it is formatted into
    any statement. The default is the day before the run's *scheduled* UTC
    start, not ``date.today()``: the worker's wall clock and local timezone
    would drift from the schedule, and a late-starting run would silently claim
    the wrong day. This matches what ``{{ ds }}`` names in the Airflow DAG.
    """
    if run_date is not None:
        return date.fromisoformat(run_date).isoformat()

    scheduled = flow_run.scheduled_start_time
    scheduled_utc = scheduled.astimezone(timezone.utc).date()
    return (scheduled_utc - timedelta(days=1)).isoformat()


def _retry_only_when_missing(task, task_run, state) -> bool:
    """Retry the wait only for a missing key; fail fast on real errors.

    A bad credential returns 403, not 404. Treating that as not-yet-there would
    burn the whole retry budget on a misconfiguration, so only a missing-object
    error keeps polling.
    """
    exception = state.result(raise_on_failure=False)
    if isinstance(exception, ClientError):
        code = exception.response.get("Error", {}).get("Code", "")
        return code in {"404", "NoSuchKey", "NotFound"}
    return False


@task(retries=2, retry_delay_seconds=30)
def run_statement(block_name: str, sql: str) -> None:
    """Run one trusted statement.

    COPY and DML run in an explicit transaction. CALL does not: Chapter 9's
    procedure opens its own scoped transaction, and Snowflake rejects a CALL
    nested inside an outer one (error 090232).
    """
    _validate_block_name(block_name)
    is_call = sql.lstrip().upper().startswith("CALL")
    with SnowflakeConnector.load(block_name) as connector:
        connection = connector.get_connection(autocommit=is_call)
        if is_call:
            connector.execute(sql)
            return
        try:
            connector.execute(sql)
            connection.commit()
        except SnowflakeError:
            connection.rollback()
            raise


@task(retries=2, retry_delay_seconds=30)
def rebuild_revenue_partition(block_name: str, run_date: str) -> None:
    """Replace one day's revenue rows inside a single transaction.

    The connection is opened with autocommit off, so the DELETE and the INSERT
    commit together when the task finishes and roll back together if either
    fails. A retry therefore cannot leave the day half-written.
    """
    _validate_block_name(block_name)
    with SnowflakeConnector.load(block_name) as connector:
        connection = connector.get_connection(autocommit=False)
        try:
            connector.execute(DELETE_REVENUE_SQL, parameters={"run_date": run_date})
            connector.execute(INSERT_REVENUE_SQL, parameters={"run_date": run_date})
            connection.commit()
        except SnowflakeError:
            connection.rollback()
            raise


@task(
    retries=60,
    retry_delay_seconds=60,
    retry_condition_fn=_retry_only_when_missing,
)
def wait_for_scores(run_date: str) -> str:
    """Poll S3 for the run's dated scores file, one head_object per attempt.

    The retry policy is the whole waiting mechanism. Note what it costs: unlike
    an Airflow deferred sensor, the flow run and the infrastructure hosting it
    stay alive for the full poll window.
    """
    key = f"scores/fraud_scores_{run_date}.parquet"
    boto3.client("s3").head_object(Bucket=SCORES_BUCKET, Key=key)
    return key


@task(retries=2, retry_delay_seconds=30)
def push_segment(block_name: str, run_date: str) -> None:
    """Query the high-risk segment for the run's day and POST it out."""
    _validate_block_name(block_name)
    with SnowflakeConnector.load(block_name) as connector:
        rows = connector.fetch_all(SEGMENT_SQL, parameters={"run_date": run_date})

    # Snowflake returns NUMBER columns as Decimal, which the JSON encoder
    # cannot serialize; float() matches what the Airflow and Dagster pushes do.
    segment = [
        {
            "merchant_id": merchant_id,
            "revenue": float(revenue),
            "risk": float(risk),
        }
        for merchant_id, revenue, risk in rows
    ]

    # The key is the day, so a replay of that day presents the key it presented
    # the first time and the marketing tool deduplicates it.
    response = httpx.post(
        MARKETING_URL,
        json=segment,
        headers={"Idempotency-Key": f"techflow-{run_date}"},
        timeout=30,
    )
    response.raise_for_status()


@flow(name="techflow-transform", log_prints=True)
def techflow_transform(
    block_name: str = "techflow-snowflake",
    run_date: str | None = None,
) -> None:
    """Wait, load, cleanse, run dbt, aggregate, and push, in that order."""
    run_date = _resolve_run_date(run_date)

    scores = wait_for_scores.submit(run_date)
    load = run_statement.submit(
        block_name,
        COPY_SCORES_SQL.format(run_date=run_date),
        wait_for=[scores],
    )
    cleanse = run_statement.submit(block_name, CLEANSE_SQL, wait_for=[load])

    # Resolve the cleanse before the plain dbt call so the build never races it.
    # .result() re-raises, so a failed cleanse stops the flow here; .wait()
    # would block without raising and let dbt run on unclean data.
    cleanse.result()
    PrefectDbtRunner(
        settings=PrefectDbtSettings(project_dir=str(DBT_PROJECT_DIR))
    ).invoke(["build", "--select", "tag:nightly"])

    aggregate = rebuild_revenue_partition.submit(block_name, run_date)
    push = push_segment.submit(block_name, run_date, wait_for=[aggregate])

    # Prefect requires the terminal future resolved; .result() re-raises a
    # failure so the flow reports the broken run instead of a false success.
    push.result()


if __name__ == "__main__":
    techflow_transform()
