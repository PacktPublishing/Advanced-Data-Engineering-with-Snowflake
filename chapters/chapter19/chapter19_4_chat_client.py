"""Chapter 19, section 4.4: a streaming, multi-turn terminal client for PAYMENT_ANALYST.

Needs: chapter19_4_agents.sql already run, plus a programmatic access token for the test
user whose ROLE_RESTRICTION names the role you are testing (Chapter 13 token pattern). Run as
USERADMIN, which owns the test user when the setup's test user block created it:
    ALTER USER <REPLACE: test user name> ADD PROGRAMMATIC ACCESS TOKEN payment_chat
        ROLE_RESTRICTION = 'BI_READER' DAYS_TO_EXPIRY = 1;
    export SNOWFLAKE_PAT='<REPLACE: token secret>'
    export SNOWFLAKE_ACCOUNT_URL='https://<REPLACE: account_identifier>.snowflakecomputing.com'
Repeat with a NO_DATA_READER token named payment_chat_restricted. The agent rejects that
run with an HTTP 4XX error because its spec sets tool_not_accessible: reject.
Validation: run live on the author's sandbox account on 2026-10-24 for both identities. The
SQL branch reads response.tool_result, where that run found the generated SQL; the revised
branch was rerun live the same day and printed the SQL for both turns.
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
                yield event, _parse("\n".join(data))
            event, data = None, []
        elif line.startswith("event:"):
            event = line[len("event:"):].strip()
        elif line.startswith("data:"):
            data.append(line[len("data:"):].strip())
    if data:  # a stream that ends without a trailing blank line
        yield event, _parse("\n".join(data))


def _parse(payload):
    """Decode one event payload; keep non-JSON text instead of crashing."""
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return {"text": payload}


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
            elif event == "response.tool_result":
                for item in data.get("content", []):
                    statement = (item.get("json") or {}).get("sql")
                    if statement:
                        sql[data.get("tool_use_id", "tool")] = statement
            elif event == "metadata" and data["metadata"]["role"] == "assistant":
                assistant_id = data["metadata"]["message_id"]
            elif event == "response.warning":
                print(f"\n[warning] {data.get('message', data)}")
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
    if not thread.ok:
        raise SystemExit(f"Thread creation failed, HTTP {thread.status_code}: "
                         f"{thread.text[:500]}")
    thread_id, parent_id = int(thread.json()["thread_id"]), 0
    while True:
        question = input("\nquestion> ").strip()
        if question.lower() in {"", "quit", "exit"}:
            break
        try:
            assistant_id = ask(thread_id, parent_id, question)
        except requests.RequestException as exc:
            print(f"Request failed: {exc}")
            continue
        if assistant_id is not None:
            parent_id = assistant_id  # follow-ups continue from this answer


if __name__ == "__main__":
    main()
