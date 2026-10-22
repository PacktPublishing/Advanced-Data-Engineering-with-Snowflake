#!/usr/bin/env bash
# Chapter 15 re-validation after the 2026-09-20 rename (GOVERNANCE_DB + five plain roles).
# Run on the Mac, where the Snowflake CLI `book` connection is configured.
# Logs land in ./logs/ next to the scripts; nothing is written to GOLD_DB.
set -u
cd "$(dirname "$0")"
mkdir -p logs
FILES=(
  chapter15_0_setup.sql
  chapter15_1_tagging.sql
  chapter15_2_masking.sql
  chapter15_3_row_security.sql
  chapter15_4_quality.sql
  chapter15_5_documentation.sql
  chapter15_live_checks.sql
)
for f in "${FILES[@]}"; do
  ts=$(date -u +%H:%M:%S)
  echo "== ${ts}Z  ${f}"
  if snow sql -c book -f "$f" --format json > "logs/${f%.sql}.log" 2>&1; then
    if [[ "$f" == chapter15_live_checks.sql ]]; then
      # A successful SELECT can still report PASSED=false. Fail the run on
      # false, NULL, or missing assertions instead of trusting the CLI status.
      if ! python3 - "logs/${f%.sql}.log" <<'PY'
import json
import sys

with open(sys.argv[1]) as result_file:
    results = json.load(result_file)
checks = [row for result in results for row in result if 'PASSED' in row]
failed = [row.get('TEST', '<unnamed>') for row in checks if row['PASSED'] is not True]
if not checks or failed:
    sys.exit(f'Live assertions failed or missing: {failed or "no PASSED results"}')
print(f'   {len(checks)} live assertions passed')
PY
      then
        echo "   FAILED assertions -> logs/${f%.sql}.log  [stopping]"
        exit 1
      fi
    fi
    echo "   ok   -> logs/${f%.sql}.log"
  else
    echo "   FAILED (rc=$?) -> logs/${f%.sql}.log  [stopping]"
    tail -20 "logs/${f%.sql}.log"
    exit 1
  fi
done
echo "== done. Section 4 blocks on two scheduled observations, so a 20-45 minute run is normal."
echo "== teardown is deliberately NOT run here: chapter15_teardown.sql when you are finished."
