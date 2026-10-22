#!/usr/bin/env bash
set -euo pipefail

# Chapter 7: run the local unit tier; integration tier only when CI env is set.

if [ -z "${VIRTUAL_ENV:-}" ]; then
    source .venv/bin/activate
fi

pytest -q tests/unit

if [ -n "${SNOWFLAKE_CONNECTION_NAME:-}" ]; then
    pytest -q tests/integration
else
    echo "Skipping tests/integration (set SNOWFLAKE_CONNECTION_NAME to opt in)."
fi
