#!/usr/bin/env bash
# Chapter 6, Section 4 -- CoCo CLI command snippets, in chapter order.
# Captured commands, not an installer: run them one at a time. The bare
# `cortex` call opens an interactive session (first run: connection wizard
# against ~/.snowflake/connections.toml), so do not pipe this file into a shell.
set -euo pipefail

# 4.1 step 2: install and verify (binary lands in ~/.local/bin as `cortex`).
curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh | sh
cortex --version

# 4.1 step 3: first run opens the setup wizard; pick or create a connection.
# `cortex auth login` re-runs authentication alone; `cortex -c <name>` pins a
# specific connection. `/status` inside a session shows which connection (and
# billing account) the agent is on.
cortex

# 4.1 step 4: one-shot smoke test (-p runs a single prompt and exits).
cortex -p "list the tables in silver_db.customers and describe the silver_customers columns"

# 4.2 step 3: confirm AGENTS.md is loaded.
cortex -p "summarize the project rules you currently know about"

# 4.3 step 4: invoke the custom skill explicitly with the $ prefix.
cortex -p "\$dbt-incremental-model refactor int_sales__customer into an incremental model with account_id as the natural key and account_name, account_type as the tracked attribute columns"
