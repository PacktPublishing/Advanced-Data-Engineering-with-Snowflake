"""Chapter 19, section 4.4: a streaming, multi-turn terminal client for PAYMENT_ANALYST.

Needs: chapter19_4_agents.sql already run, plus a programmatic access token whose
ROLE_RESTRICTION names the identity you are testing (Chapter 13, section 4.1 pattern):
    ALTER USER ADD PROGRAMMATIC ACCESS TOKEN payment_chat
        ROLE_RESTRICTION = 'BI_READER' DAYS_TO_EXPIRY = 1;
    export SNOWFLAKE_PAT='<REPLACE: token secret>'
    export SNOWFLAKE_ACCOUNT_URL='https://<REPLACE: account_identifier>.snowflakecomputing.com'
Repeat with a NO_DATA_READER token for the restricted-identity case.
Validation: syntax and the event parser checked locally against documented event
shapes (October 2026); not run against a live account.
A web interface must HTML-escape agent text before rendering it; this client prints to a terminal.
"""

import json
import os

import requests

ACCOUNT_URL = os.environ["SNOWFLAKE_ACCOUNT_URL"]
AGENT_URL = (f"{ACCOUNT_URL}/api/v2/databases/ANALYTICS_DB/schemas/SERVING"
             "/agents/PAYMENT_ANALYST:run")
AUTH = {"Authorization": f"Bearer {os.environ['SNOWFLAKE_PAT']}",
        "Content-Type": "application/json"}


def read_events(lines):
    """Yield (event, data) pairs from server-sent event lines."""
    event, data = None, []
    for line in lines:
        if line == "":
            if data:
                yield event, json.loads("\n".join(data))
            event, data = None, []
        elif line.startswith("event:"):
            event = line[len("event:"):].strip()
        elif line.startswith("data:"):
            data.append(line[len("data:"):].strip())
    if data:  # a stream that ends without a trailing blank line
        yield event, json.loads("\n".join(data))


def ask(thread_id, parent_id, question):
    """Stream one turn. Return the assistant message id, or None on error."""
    body = {"thread_id": thread_id, "parent_message_id": parent_id,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": question}]}],
            "stream": True}
    assistant_id, sql = None, {}
    with requests.post(AGENT_URL, json=body, stream=True, timeout=300,
                       headers={**AUTH, "Accept": "text/event-stream"}) as resp:
        if not resp.ok:
            print(f"HTTP {resp.status_code}: {resp.text[:500]}")
            return None
        resp.encoding = "utf-8"
        lines = resp.iter_lines(decode_unicode=True)
        for event, data in read_events(lines):
            if event == "response.text.delta":
                print(data["text"], end="", flush=True)
            elif event == "response.tool_result.analyst.delta":
                delta = data.get("delta", {})
                key = data.get("tool_use_id", "tool")
                sql[key] = sql.get(key, "") + delta.get("sql", "")
            elif event == "metadata" and data["metadata"]["role"] == "assistant":
                assistant_id = data["metadata"]["message_id"]
            elif event == "error":
                print(f"\n[error {data.get('code')}] {data.get('message')}")
                return None
    for statement in filter(None, sql.values()):
        print(f"\n[SQL]\n{statement}")
    print()
    return assistant_id


def main():
    thread = requests.post(f"{ACCOUNT_URL}/api/v2/cortex/threads",
                           headers={**AUTH, "Accept": "application/json"},
                           json={"origin_application": "ch19_chat"}, timeout=30)
    thread.raise_for_status()
    thread_id, parent_id = int(thread.json()["thread_id"]), 0
    while True:
        question = input("\nquestion> ").strip()
        if question.lower() in {"", "quit", "exit"}:
            break
        assistant_id = ask(thread_id, parent_id, question)
        if assistant_id is not None:
            parent_id = assistant_id  # follow-ups continue from this answer


if __name__ == "__main__":
    main()
