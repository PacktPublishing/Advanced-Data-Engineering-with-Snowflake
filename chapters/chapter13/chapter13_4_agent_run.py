# =============================================================================
# Chapter 13, Section 5.2: Running the Agent via the REST API
# Needs: chapter13_4_agent.sql already run (the agent object), plus the same
#   credentials as chapter13_3_analyst_api.py:
#       export SNOWFLAKE_PAT='<REPLACE: token from Snowsight settings>'
#       export SNOWFLAKE_ACCOUNT_URL='https://<account_identifier>.snowflakecomputing.com'
# Tested August 2026 with Python 3.11 and requests.
#
# Named-agent :run requires a thread. Create one first, then pass thread_id
# and parent_message_id=0 on the first turn. See:
#   https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-threads
# =============================================================================

import os
import requests

ACCOUNT_URL = os.environ.get(
    "SNOWFLAKE_ACCOUNT_URL",
    "https://<REPLACE: account_identifier>.snowflakecomputing.com")
HEADERS = {
    "Authorization": f"Bearer {os.environ['SNOWFLAKE_PAT']}",
    "Content-Type": "application/json",
    "Accept": "application/json",
}

thread = requests.post(
    f"{ACCOUNT_URL}/api/v2/cortex/threads",
    headers=HEADERS,
    json={"origin_application": "ch13"},
    timeout=30)
thread.raise_for_status()
thread_id = int(thread.json()["thread_id"])

body = {
    "thread_id": thread_id,
    "parent_message_id": 0,
    "messages": [{
        "role": "user",
        "content": [{"type": "text",
                     "text": "Which merchant categories drove refund"
                             " spikes last quarter, and what were"
                             " customers complaining about?"}],
    }],
    "stream": False,
}

resp = requests.post(
    f"{ACCOUNT_URL}/api/v2/databases/gold_db/schemas/support"
    "/agents/techflow_assistant:run",
    headers=HEADERS, json=body, timeout=120)
if not resp.ok:
    raise SystemExit(f"{resp.status_code} {resp.reason}: {resp.text[:2000]}")

# Expect a composed answer with refund figures (from the revenue tool) and
# cited ticket ids (from the tickets tool). With "stream": True the response
# becomes server-sent events, including tool-use progress events.
# Follow-ups: pass this thread_id plus the assistant message_id from the
# response metadata as parent_message_id.
print(resp.json())
