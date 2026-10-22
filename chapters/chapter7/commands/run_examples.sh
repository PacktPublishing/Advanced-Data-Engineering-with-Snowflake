#!/usr/bin/env bash
set -euo pipefail

# Chapter 7: walk through the chapter examples end to end.
# Assumes chapter7_setup.sql ran and deploy_udfs.sh has been executed.

if [ -z "${VIRTUAL_ENV:-}" ]; then
    source .venv/bin/activate
fi

echo "==> Section 1.2 monthly_revenue"
python -m snowpark.dataframe_api.monthly_revenue

echo "==> Section 1.3 explain plan"
python -m snowpark.dataframe_api.explain_plan

echo "==> Section 1.2 benchmark (1M-row default)"
python -m snowpark.dataframe_api.benchmark_pushdown --limit 1000000

echo "==> Section 2.1 pandas on Snowflake"
python -m snowpark.pandas_on_snowflake.read_snowflake_demo

echo "==> Section 2.2 fallback warning demo"
python -m snowpark.pandas_on_snowflake.fallback_demo
