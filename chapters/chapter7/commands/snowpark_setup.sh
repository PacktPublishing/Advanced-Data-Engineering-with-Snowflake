#!/usr/bin/env bash
set -euo pipefail

# Chapter 7: one-time Snowpark Python environment bootstrap.
# Run from chapters/chapter7/.

python3.11 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

mkdir -p "$HOME/.snowflake"
if [ ! -f "$HOME/.snowflake/config.toml" ]; then
    cp config.toml.example "$HOME/.snowflake/config.toml"
    chmod 600 "$HOME/.snowflake/config.toml"
    echo "Copied config.toml.example to ~/.snowflake/config.toml: edit it before running anything else."
else
    echo "~/.snowflake/config.toml already exists; leaving it untouched."
fi

snow --version >/dev/null 2>&1 || {
    echo "Snowflake CLI (snow) is not on PATH. Install it before running chapter7_setup.sql."
    exit 1
}

echo "Next: run chapter7_setup.sql to create stages, control tables, and seed data."
echo "    snow sql -c default -f chapter7_setup.sql"
