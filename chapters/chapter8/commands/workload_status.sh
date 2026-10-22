#!/usr/bin/env bash
set -euo pipefail

# Chapter 8, Section 3.2, step 2: check status and logs from the CLI.
# Pass the SUFFIXED workload name that submit_daily_settlement.sh printed,
# e.g. ./commands/workload_status.sh DAILY_SETTLEMENT_260610_213045
#
# The status call returns one of DEPLOYING, RUNNING, SUCCEEDED, or FAILED along
# with start time, duration, and service details. --display-logs prints the
# application logs, which have a short retention window by default (a few
# minutes after the run) unless an event table captures them.

if [ -z "${VIRTUAL_ENV:-}" ]; then
    source .venv/bin/activate
fi

WORKLOAD_NAME="${1:?Pass the suffixed workload name, e.g. DAILY_SETTLEMENT_260610_213045}"

snowpark-submit \
  --snowflake-connection-name spark-connect \
  --snowflake-workload-name "${WORKLOAD_NAME}" \
  --workload-status --display-logs
