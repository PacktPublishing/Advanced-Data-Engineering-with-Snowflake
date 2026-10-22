#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly COMPONENT_PATH="${PROJECT_ROOT}/src/techflow_orchestration/defs/techflow_dbt"
declare -ar SCAFFOLD_COMMAND=(
  dg
  scaffold
  defs
  dagster_dbt.DbtProjectComponent
  techflow_dbt
  --project-path
  ../../chapter6/dbt/techflow_warehouse
)

print_command() {
  printf 'Review this command before it writes component files:\n\n'
  printf '  %q' "${SCAFFOLD_COMMAND[@]}"
  printf '\n'
}

print_command

if [[ "${1:-}" != "--apply" ]]; then
  printf '\nNo files changed. Re-run with --apply after review.\n'
  exit 0
fi

if [[ -e "${COMPONENT_PATH}" ]]; then
  printf 'Refusing to overwrite existing component: %s\n' "${COMPONENT_PATH}" >&2
  exit 1
fi

if ! command -v dg >/dev/null 2>&1; then
  printf 'The dg command is not available in PATH.\n' >&2
  exit 1
fi

cd -- "${PROJECT_ROOT}"
"${SCAFFOLD_COMMAND[@]}"
