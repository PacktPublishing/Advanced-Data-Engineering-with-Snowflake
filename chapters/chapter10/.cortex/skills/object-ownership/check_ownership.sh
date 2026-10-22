#!/usr/bin/env bash
# One-object-one-owner check (Chapter 10, Table 10.1).
# Compares object names managed by the Terraform root (infra/) against the
# DEFINE statements in the DCM project (techflow_pipeline/). Any name that
# appears in both is a two-owner violation: each tool will undo the other on
# every run. Native scripts (native/) are deliberately out of scope: they are
# one-time teaching steps, the shared stream, and unsupported types, not a
# reconciling owner that fights another tool.
set -euo pipefail
cd "$(dirname "$0")/../../.."

# Chapter policy: the shared stream stays in native SQL while DEFINE STREAM
# is preview. A definition in either DCM target would introduce another owner.
if grep -RniE '^[[:space:]]*DEFINE[[:space:]]+STREAM[[:space:]]' techflow_pipeline/sources/definitions; then
  echo "OWNERSHIP VIOLATION: the shared stream is owned by native SQL in this chapter."
  exit 1
fi

tf_names=$(grep -rhoE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"[A-Za-z0-9_]+"' infra \
  | sed -E 's/.*"([A-Za-z0-9_]+)"/\1/' | tr '[:lower:]' '[:upper:]' | sort -u)

dcm_segments=$(grep -rhoiE 'DEFINE[[:space:]]+(DYNAMIC[[:space:]]+TABLE|WAREHOUSE|DATABASE|ROLE|SCHEMA|TABLE|TASK|VIEW)[[:space:]]+[A-Za-z0-9_{}. ]+' \
    techflow_pipeline/sources/definitions 2>/dev/null \
  | sed -E 's/\{\{[^}]*\}\}//g; s/;.*$//' \
  | awk '{print $NF}' | tr '.' '\n' | tr '[:lower:]' '[:upper:]' | sort -u)

collisions=$(comm -12 <(echo "$tf_names") <(echo "$dcm_segments") | sed '/^$/d' || true)

if [ -n "$collisions" ]; then
  echo "OWNERSHIP VIOLATION: defined in both Terraform (infra/) and DCM (techflow_pipeline/):"
  echo "$collisions"
  echo "Fix: keep the object in its Table 10.1 owner and remove it from the other tool."
  exit 1
fi
echo "one-object-one-owner check passed: no name is managed by both Terraform and DCM."
