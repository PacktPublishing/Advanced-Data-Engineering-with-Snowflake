#!/usr/bin/env bash
set -euo pipefail

# Chapter 8, Sections 1.3 and 3.1: local environment bootstrap.
# Run from chapters/chapter8/ before the connection and SQL setup steps.
# Prerequisites: Python 3.11 (recommended) or 3.12, pip, and the Snowflake CLI.
# Validation versions are recorded in README.md. No Snowflake role is used here;
# select the configured role when running chapter8_setup.sql separately.
# No reader-specific placeholders are required in this script.

chapter8_python="${CHAPTER8_PYTHON:-python3.11}"
if ! command -v "$chapter8_python" >/dev/null 2>&1; then
    echo "Python interpreter not found: $chapter8_python. Install Python 3.11 or set CHAPTER8_PYTHON to Python 3.12." >&2
    exit 1
fi
"$chapter8_python" -c 'import sys; sys.exit(0 if sys.version_info[:2] in {(3, 11), (3, 12)} else "Chapter 8 requires Python 3.11 or 3.12; Python 3.10 reaches end of life in October 2026.")'

# An existing environment must match the selected interpreter; venv does not
# safely change the minor version of an environment in place.
if [ -e .venv ]; then
    if [ ! -x .venv/bin/python ]; then
        echo "The existing .venv has no working Python. Move it aside before rerunning setup." >&2
        exit 1
    fi
    selected_version=$("$chapter8_python" -c 'import sys; print(sys.version_info[:2])')
    existing_version=$(.venv/bin/python -c 'import sys; print(sys.version_info[:2])')
    if [ "$existing_version" != "$selected_version" ]; then
        echo "The existing .venv uses $existing_version; the selected interpreter uses $selected_version. Move .venv aside before rerunning setup." >&2
        exit 1
    fi
fi

# Section 1.3, step 1: the [jdk] extra bundles the Java runtime the local
# translation server needs, and pulls the matching pyspark 3.5.x client.
"$chapter8_python" -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m pip check

# Section 3.1, step 1: confirm the submit CLI is on PATH.
snowpark-submit -h >/dev/null 2>&1
echo "snowpark-submit OK"

mkdir -p "$HOME/.snowflake"
if [ ! -f "$HOME/.snowflake/config.toml" ]; then
    cp config.toml.example "$HOME/.snowflake/config.toml"
    chmod 600 "$HOME/.snowflake/config.toml"
    echo "Copied config.toml.example to ~/.snowflake/config.toml: edit it before running anything else."
else
    echo "~/.snowflake/config.toml already exists; leaving it untouched."
fi

# Section 1.3, step 2: add and test the spark-connect connection profile.
snow --version >/dev/null 2>&1 || {
    echo "Snowflake CLI (snow) is not on PATH. Install it (pipx install snowflake-cli) before continuing."
    exit 1
}
echo "Next: snow connection add (name it spark-connect), then:"
echo "    snow connection test --connection spark-connect"
echo "Then run chapter8_setup.sql to create the compute pool, grants, and external table:"
echo "    snow sql -c spark-connect -f chapter8_setup.sql"
