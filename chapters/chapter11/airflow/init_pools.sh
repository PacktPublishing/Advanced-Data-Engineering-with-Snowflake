#!/usr/bin/env bash
# Chapter 11, Section 5.2: create the Snowflake concurrency pool.
#
# Every Snowflake-touching task in this chapter declares pool="snowflake_book_wh",
# so this pool is the ceiling on how many statements the orchestrator can have
# in flight against BOOK_WH at once, across every DAG, run, and backfill.
#
# Size it for tasks times dbt threads, not tasks alone: one Cosmos model task
# with threads=4 consumes four warehouse connections while holding one slot.
#
# Run once against a running Airflow instance:
#   nerdctl compose exec airflow ./init_pools.sh
#   docker compose exec airflow ./init_pools.sh
set -euo pipefail

airflow pools set \
  snowflake_book_wh \
  4 \
  "Caps concurrent statements issued against BOOK_WH by all TechFlow DAGs"

airflow pools list
