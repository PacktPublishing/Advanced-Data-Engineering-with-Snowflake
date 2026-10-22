#!/usr/bin/env bash
#
# Chapter 6, Section 1: dbt Core setup and the build loop.
#
# Default mode runs only the non-mutating commands: deps, debug, parse, compile,
# and source freshness. `dbt build` and the docs server create or replace objects
# in your account and hold a port, so they run only with --apply after you have
# reviewed the compiled SQL under target/compiled/.

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CHAPTER_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_DIR="${CHAPTER_DIR}/dbt/techflow_warehouse"

cd -- "${CHAPTER_DIR}"

if [[ ! -d .venv ]]; then
    python3 -m venv .venv
fi
# shellcheck source=/dev/null
source .venv/bin/activate
pip install --quiet -r requirements.txt

cd -- "${PROJECT_DIR}"

echo "==> Non-mutating checks"
dbt deps
dbt debug
dbt parse
dbt compile
dbt source freshness

if [[ "${1:-}" != "--apply" ]]; then
    cat <<'MSG'

Reviewed nothing yet, so nothing was built.

Compiled SQL is under target/compiled/. Read it, confirm the target schemas are
the ones you expect, then re-run with --apply to execute:

    ./commands/dbt_commands.sh --apply

MSG
    exit 0
fi

echo "==> Building (creates or replaces objects in your account)"
dbt build

echo "==> Generating docs"
dbt docs generate

echo "==> Serving docs on :8080 (Ctrl-C to stop)"
dbt docs serve --port 8080
