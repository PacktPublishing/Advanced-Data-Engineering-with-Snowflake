#!/usr/bin/env bash
set -euo pipefail

# Generate (or merge into) ~/.cursor/mcp.json for the book's MCP server.
# Usage:
#   ./generate_mcp_config.sh \
#     --account-url "https://ORG-ACCT.snowflakecomputing.com" \
#     --database MEDCORE_DEMO \
#     --schema CLINICAL \
#     --mcp-server book_sql_exec_server \
#     --pat "eyJraWQ..."

ACCOUNT_URL=""
DATABASE="MEDCORE_DEMO"
SCHEMA="CLINICAL"
MCP_SERVER="book_sql_exec_server"
PAT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --account-url) ACCOUNT_URL="$2"; shift 2 ;;
    --database)    DATABASE="$2";    shift 2 ;;
    --schema)      SCHEMA="$2";      shift 2 ;;
    --mcp-server)  MCP_SERVER="$2";  shift 2 ;;
    --pat)         PAT="$2";         shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$ACCOUNT_URL" || -z "$PAT" ]]; then
  echo "Error: --account-url and --pat are required."
  echo "Usage: $0 --account-url <url> --pat <token> [--database DB] [--schema SCHEMA] [--mcp-server NAME]"
  exit 1
fi

ACCOUNT_URL="${ACCOUNT_URL%/}"

MCP_ENDPOINT="${ACCOUNT_URL}/api/v2/databases/${DATABASE}/schemas/${SCHEMA}/mcp-servers/${MCP_SERVER}"

MCP_JSON_DIR="$HOME/.cursor"
MCP_JSON_FILE="$MCP_JSON_DIR/mcp.json"

mkdir -p "$MCP_JSON_DIR"

SERVER_NAME="SnowflakeBookMCPServer"

NEW_ENTRY=$(cat <<EOF
{
  "url": "${MCP_ENDPOINT}",
  "headers": {
    "Authorization": "Bearer ${PAT}"
  }
}
EOF
)

if [[ -f "$MCP_JSON_FILE" ]]; then
  if command -v jq &>/dev/null; then
    UPDATED=$(jq --arg name "$SERVER_NAME" --argjson entry "$NEW_ENTRY" \
      '.mcpServers[$name] = $entry' "$MCP_JSON_FILE")
    echo "$UPDATED" > "$MCP_JSON_FILE"
    echo "Updated existing $MCP_JSON_FILE — added/replaced '$SERVER_NAME'."
  else
    echo ""
    echo "!! jq not found — cannot merge automatically."
    echo "Add this entry to $MCP_JSON_FILE under \"mcpServers\":"
    echo ""
    echo "  \"$SERVER_NAME\": $NEW_ENTRY"
    echo ""
    exit 0
  fi
else
  cat > "$MCP_JSON_FILE" <<MCPEOF
{
  "mcpServers": {
    "${SERVER_NAME}": ${NEW_ENTRY}
  }
}
MCPEOF
  echo "Created $MCP_JSON_FILE with '$SERVER_NAME'."
fi

chmod 600 "$MCP_JSON_FILE"
echo "Restart Cursor to activate the MCP connection."
