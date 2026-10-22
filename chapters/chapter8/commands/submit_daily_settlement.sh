#!/usr/bin/env bash
set -euo pipefail

# Chapter 8, Section 3.2, step 1: submit the settlement job interactively.
# --wait-for-completion blocks the terminal until the workload finishes, which
# is the right mode for a first run because the outcome is immediate.
#
# The command prints two values worth saving:
#   1. The full workload name with a timestamp suffix the CLI appends, e.g.
#      DAILY_SETTLEMENT_260610_213045. Status lookups only work against this
#      suffixed name (see workload_status.sh).
#   2. A Job History URL that opens the workload in Snowsight.

if [ -z "${VIRTUAL_ENV:-}" ]; then
    source .venv/bin/activate
fi

snowpark-submit \
  --snowflake-workload-name DAILY_SETTLEMENT \
  --snowflake-connection-name spark-connect \
  --compute-pool TECHFLOW_SPARK_POOL \
  --wait-for-completion \
  jobs/daily_settlement.py
