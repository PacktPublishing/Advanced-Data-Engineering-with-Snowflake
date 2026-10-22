# =============================================================================
# Chapter 13, Section 4: Integrating Cortex Analyst Through the REST API
# Needs: the Chapter 12 semantic view gold_db.semantic.techflow_revenue
#   (run the chapter12 companion scripts first), plus a programmatic access
#   token in the SNOWFLAKE_PAT environment variable:
#       export SNOWFLAKE_PAT='<REPLACE: token from Snowsight settings>'
#   With no network policy on the account (typical on trials), a person
#   user's PAT does not authenticate. For a short exercise, create the token
#   in SQL with a temporary exemption (chapter Section 4.1):
#       ALTER USER ADD PROGRAMMATIC ACCESS TOKEN techflow_api
#           ROLE_RESTRICTION = '<REPLACE: your_role>'
#           DAYS_TO_EXPIRY = 1
#           MINS_TO_BYPASS_NETWORK_POLICY_REQUIREMENT = 240;
# Replace <REPLACE: account_identifier> below with your account identifier.
# Tested August 2026 with Python 3.11 and requests.
#
# Cortex Analyst generates SQL and never executes it; execution happens in
# this client through the statements API, as your role, on your warehouse.
# =============================================================================

import os
import requests

ACCOUNT_URL = os.environ.get(
    "SNOWFLAKE_ACCOUNT_URL",
    "https://<REPLACE: account_identifier>.snowflakecomputing.com")
HEADERS = {
    "Authorization": f"Bearer {os.environ['SNOWFLAKE_PAT']}",
    "Content-Type": "application/json",
}

# --- 4.1 Ask the question (same one Chapter 12 asked in Snowsight) ----------
body = {
    "messages": [{
        "role": "user",
        "content": [{"type": "text",
                     "text": "What was total revenue by month?"}],
    }],
    "semantic_view": "gold_db.semantic.techflow_revenue",
}

resp = requests.post(
    f"{ACCOUNT_URL}/api/v2/cortex/analyst/message",
    headers=HEADERS, json=body, timeout=60)
resp.raise_for_status()
analyst_msg = resp.json()["message"]

# Interpretation text, generated SQL, and (if the Chapter 12 verified query
# matched) a confidence report naming it.
for c in analyst_msg["content"]:
    print(c["type"], ":", str(c)[:120])

# --- 4.2 Execute the returned SQL as *your* role ----------------------------
sql = next(c["statement"] for c in analyst_msg["content"]
           if c["type"] == "sql")

run = requests.post(
    f"{ACCOUNT_URL}/api/v2/statements",
    headers=HEADERS,
    json={"statement": sql, "warehouse": "BOOK_WH"},
    timeout=60)
run.raise_for_status()
# Expect the month/revenue rows to match the Chapter 12 Snowsight answer:
# both paths read one semantic view.
print(run.json()["data"][:3])

# --- 4.3 Options, for reference ---------------------------------------------
# Streaming: add "stream": True to the message request and consume
#   server-sent events instead of one JSON body.
# Multi-view routing: replace "semantic_view" with
#   "semantic_models": [{"semantic_view": "gold_db.semantic.techflow_revenue"},
#                       {"semantic_view": "<another view>"}]
#   and Cortex Analyst picks the view per question.
