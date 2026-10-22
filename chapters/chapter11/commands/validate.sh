#!/usr/bin/env bash
#
# Chapter 11 non-mutating validation.
#
# Runs syntax, import-safe topology, YAML, Docker Compose, SQL, and dbt parse
# checks. It never triggers an orchestrator, saves a Prefect block, materializes
# a Dagster asset, or opens a Snowflake connection. Every data-modifying SQL
# statement stays behind human review.

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CHAPTER_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

cd -- "${CHAPTER_DIR}"

echo "==> Compiling companion Python"
python3 -m compileall -q airflow prefect dagster tests upload_scores.py marketing_api

echo "==> Running non-mutating unit tests"
# test_dags.py is pytest-only (needs Airflow). unittest discover imports every
# test_*.py and would fail on `import pytest` before any skip can run.
python3 -m unittest tests.test_companion_static tests.test_prefect_config

echo "==> Parsing chapter YAML"
uv run --no-project --with pyyaml python3 - <<'PY'
import glob
import sys

import yaml

files = sorted(
    p
    for p in glob.glob("**/*.yml", recursive=True)
    + glob.glob("**/*.yaml", recursive=True)
    if "_to_delete" not in p.split("/")
)
failures = []
for path in files:
    try:
        list(yaml.safe_load_all(open(path)))
    except yaml.YAMLError as error:
        failures.append((path, str(error)))

print(f"parsed {len(files)} YAML files")
for path, error in failures:
    print(f"FAIL {path}: {error}")
sys.exit(1 if failures else 0)
PY

echo "==> Validating Airflow Compose config"
# Rancher Desktop with containerd has no Docker API; use nerdctl there.
if docker info >/dev/null 2>&1; then
    docker compose -f airflow/docker-compose.yml config >/dev/null
elif command -v nerdctl >/dev/null 2>&1 && nerdctl info >/dev/null 2>&1; then
    nerdctl compose -f airflow/docker-compose.yml config >/dev/null
else
    echo "FAIL: need a running container engine (docker, or nerdctl on Rancher Desktop/containerd)" >&2
    exit 1
fi

echo "==> Parsing plain SQL with sqlfluff (Snowflake dialect)"
uv run --no-project --with sqlfluff python3 - <<'PY'
import subprocess
import sys

plain_sql = [
    "airflow/dags/sql/cleanse_transactions.sql",
    "airflow/dags/sql/build_daily_revenue.sql",
    "airflow/dags/sql/build_daily_revenue_incremental.sql",
    "airflow/dags/sql/build_daily_revenue_partitioned.sql",
    "airflow/dags/sql/load_fraud_scores.sql",
    "airflow/dags/sql/load_fraud_scores_partitioned.sql",
    "sql/set_query_tag.sql",
]
failures = []
for path in plain_sql:
    code = subprocess.call(
        ["sqlfluff", "parse", "--dialect", "snowflake", "--templater", "raw", path],
        stdout=subprocess.DEVNULL,
    )
    if code != 0:
        failures.append(path)

sys.exit(1 if failures else 0)
PY

echo "==> Parsing the shared Chapter 6 dbt project with the chapter-11 additions"
# There is no chapter-11 dbt copy; all three tools run the Chapter 6
# techflow_warehouse project, extended here with the nightly merchant_activity
# mart and the transactions source. Parse it as a no-connection check.
(
    cd ../chapter6/dbt/techflow_warehouse
    profiles_dir="$(mktemp -d)"
    cp profiles.yml.example "${profiles_dir}/profiles.yml"
    export SF_ACCOUNT="${SF_ACCOUNT:-parse_only}"
    export SF_USER="${SF_USER:-parse_only}"
    export SF_PASSWORD="${SF_PASSWORD:-parse_only}"
    export SF_ROLE="${SF_ROLE:-TRANSFORMER_RL}"
    # Only install packages when they are missing. Re-running deps over an
    # existing dbt_packages can leave duplicate "<package> 2" folders behind,
    # and dbt then fails the parse on the folder with no dbt_project.yml.
    if [[ ! -d dbt_packages ]]; then
        uv run --no-project --with dbt-core --with dbt-snowflake dbt deps
    fi
    uv run --no-project --with dbt-core --with dbt-snowflake \
        dbt parse --no-partial-parse --profiles-dir "${profiles_dir}"
)

echo "==> Validating Dagster definitions (no materialization)"
# The dbt component loads the shared Chapter 6 project, which validates that a
# profiles.yml sits in the project dir. That project ships only profiles.yml.example
# (the same file every tool copies), so drop a parse-only profiles.yml in place for
# the check and remove it afterward. No connection is opened.
readonly SHARED_DBT_DIR="${CHAPTER_DIR}/../chapter6/dbt/techflow_warehouse"
cp "${SHARED_DBT_DIR}/profiles.yml.example" "${SHARED_DBT_DIR}/profiles.yml"
trap 'rm -f "${SHARED_DBT_DIR}/profiles.yml"' EXIT
(
    cd dagster
    SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT:-parse_only}" \
    SNOWFLAKE_USER="${SNOWFLAKE_USER:-parse_only}" \
    SNOWFLAKE_PRIVATE_KEY="${SNOWFLAKE_PRIVATE_KEY:-parse_only}" \
    SNOWFLAKE_PRIVATE_KEY_PATH="${SNOWFLAKE_PRIVATE_KEY_PATH:-/tmp/parse_only.p8}" \
    SF_ACCOUNT="${SF_ACCOUNT:-parse_only}" \
    SF_USER="${SF_USER:-parse_only}" \
    SF_PASSWORD="${SF_PASSWORD:-parse_only}" \
    SF_ROLE="${SF_ROLE:-TRANSFORMER_RL}" \
        uv run --no-project \
        --with dagster --with dagster-aws --with dagster-dbt \
        --with dagster-snowflake --with dbt-snowflake \
        --with dagster-dg-cli --with httpx \
        dg check defs
)
rm -f "${SHARED_DBT_DIR}/profiles.yml"
trap - EXIT

echo "==> All non-mutating checks passed"
