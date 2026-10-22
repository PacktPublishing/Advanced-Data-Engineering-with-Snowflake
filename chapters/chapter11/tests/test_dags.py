"""Chapter 11, Section 5.4: the DAG import test.

Most DAG outages are files that stopped parsing: a missing package, a renamed
import, a syntax error. One assertion catches all of them in CI, before the
next scheduled run does. Requires Airflow installed; the offline consistency
checks that need no Airflow live in tests/test_companion_static.py.

Run: pytest tests/test_dags.py
"""

from __future__ import annotations

from pathlib import Path

import pytest

pytest.importorskip("airflow", reason="Airflow is only installed in the Airflow image")

from airflow.dag_processing.dagbag import DagBag  # noqa: E402

DAGS_DIR = Path(__file__).resolve().parents[1] / "airflow" / "dags"

EXPECTED_DAG_IDS = {
    "techflow_transform",
    "fraud_scores_ingest",
    "transaction_transform",
    "marketing_activation",
}


@pytest.fixture(scope="module")
def dagbag() -> DagBag:
    # Airflow 3 dropped include_examples. The dags folder must be on sys.path
    # so sibling imports like techflow_common resolve the same way the
    # dag-processor bundle load does.
    import sys

    sys.path.insert(0, str(DAGS_DIR))
    return DagBag(dag_folder=str(DAGS_DIR))


def test_dags_import_cleanly(dagbag: DagBag) -> None:
    """No DAG file raises on import."""
    assert dagbag.import_errors == {}


def test_expected_dags_are_present(dagbag: DagBag) -> None:
    """Every DAG the chapter names exists under that id."""
    assert EXPECTED_DAG_IDS <= set(dagbag.dags)


def test_split_producers_share_a_partition_key_format(dagbag: DagBag) -> None:
    """The two producers must format partition keys identically.

    IdentityMapper matches keys as literal strings, so a mismatch here does not
    raise anywhere: marketing_activation would simply never be scheduled. That
    silence is why this is worth asserting.
    """
    ingest = dagbag.dags["fraud_scores_ingest"].timetable
    transform = dagbag.dags["transaction_transform"].timetable
    assert ingest.key_format == transform.key_format == "%Y-%m-%d"
    assert ingest.run_offset == transform.run_offset == -1


def test_snowflake_tasks_claim_the_pool(dagbag: DagBag) -> None:
    """Every task that issues SQL is bounded by the warehouse pool."""
    for dag_id in EXPECTED_DAG_IDS:
        for task in dagbag.dags[dag_id].tasks:
            if task.task_id in {"wait_for_scores"}:
                continue
            assert task.pool == "snowflake_book_wh", f"{dag_id}.{task.task_id}"
