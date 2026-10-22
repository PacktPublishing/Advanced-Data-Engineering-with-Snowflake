#!/usr/bin/env bash
#
# Chapter 6, Section 2: the SQLMesh virtual-environment loop.
#
# Default mode runs only `sqlmesh info`, which reads metadata and creates nothing.
# `plan dev` builds developer tables and `plan prod` promotes to production, so
# each needs an explicit flag:
#
#   ./commands/sqlmesh_commands.sh              # info only
#   ./commands/sqlmesh_commands.sh --plan-dev   # build the dev environment + diff
#   ./commands/sqlmesh_commands.sh --plan-prod  # promote to prod (last step)
#
# Promotion is deliberately not chained onto the dev plan: the point of the
# workflow is to read the diff before swapping the views.

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CHAPTER_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_DIR="${CHAPTER_DIR}/sqlmesh/techflow_sqlmesh"
readonly TARGET_MODEL="gold_db.customers.gold_customer_value"

cd -- "${CHAPTER_DIR}"

if [[ ! -d .venv ]]; then
    python3 -m venv .venv
fi
# shellcheck source=/dev/null
source .venv/bin/activate
pip install --quiet -r requirements.txt

cd -- "${PROJECT_DIR}"

sqlmesh --version
echo "==> Project metadata (reads only)"
sqlmesh info

case "${1:-}" in
    --plan-dev)
        echo "==> Building the dev environment; live tables stay untouched"
        sqlmesh plan dev
        echo "==> Row-level diff of dev against prod"
        sqlmesh table_diff prod:dev "${TARGET_MODEL}" \
            --on customer_id \
            --show-sample
        ;;
    --plan-prod)
        echo "==> Promoting to prod with a view swap"
        sqlmesh plan prod
        ;;
    *)
        cat <<'MSG'

Nothing was built. Re-run with a flag once you know which step you want:

    --plan-dev    build developer tables, then diff them against prod
    --plan-prod   promote to prod (only after reading the diff)

MSG
        ;;
esac
