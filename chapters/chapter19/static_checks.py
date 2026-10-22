"""Check Chapter 19 fixture, package structure, clients, and optional manuscript excerpt parity.

Run: python3 static_checks.py [absolute/path/to/chapter.md]
Requires Python 3 and PyYAML. No Snowflake/network calls or credentials.
Checks local artifacts only; does not assert Snowflake SQL execution success.
"""

import ast
import csv
from decimal import Decimal
from pathlib import Path
import re
import sys

import yaml

ROOT = Path(__file__).resolve().parent
EXPECTED_EXCERPTS = 14  # printed sql, yaml, python, and markdown blocks; the bash block is not an excerpt


def main():
    with (ROOT / "payment_fixture.csv").open(newline="") as source:
        rows = list(csv.DictReader(source))
    assert len(rows) == 12
    assert len({r["attempt_id"] for r in rows}) == 12

    def summarize(selected):
        approved = [r for r in selected if r["approved"] == "True"]
        return (len(selected), len(approved),
                sum((Decimal(r["amount_usd"]) for r in approved), Decimal(0)))

    assert summarize(rows) == (12, 7, Decimal("675"))
    assert summarize([r for r in rows if r["merchant_id"] == "M100"]) == (8, 5, Decimal("375"))
    assert summarize([r for r in rows if r["merchant_id"] == "M200"]) == (4, 2, Decimal("300"))
    first = summarize([r for r in rows if r["event_date"] == "2026-09-01"])
    second = summarize([r for r in rows if r["event_date"] == "2026-09-02"])
    assert first == (6, 4, Decimal("375")) and second == (6, 3, Decimal("300"))
    assert (second[2] - first[2]) / first[2] == Decimal("-0.2")

    setup = (ROOT / "chapter19_0_setup.sql").read_text()
    tuples = re.findall(r"\((\d+), '(2026-09-0[12])', '(M\d+)', ([\d.]+), (TRUE|FALSE)\)", setup)
    assert len(tuples) == len(rows), "SQL fixture count differs from CSV"
    for sql_row, csv_row in zip(tuples, rows):
        i, date, merchant, amount, approved = sql_row
        assert (i, date, merchant, Decimal(amount), approved == "TRUE") == (
            csv_row["attempt_id"], csv_row["event_date"], csv_row["merchant_id"],
            Decimal(csv_row["amount_usd"]), csv_row["approved"] == "True")
    assert "CREATE OR REPLACE VIEW" not in setup, "the reporting view belongs to chapter19_1_bi.sql"

    bi = (ROOT / "chapter19_1_bi.sql").read_text()
    assert "STATEMENT_TIMEOUT_IN_SECONDS = 120" in bi and "AUTO_SUSPEND = 300" in bi

    interactive = (ROOT / "chapter19_2_interactive.sql").read_text()
    assert "AUTO_SUSPEND = 86400" in interactive, "interactive warehouse must cap idle billing"
    assert "ZIPF(1, 2000, RANDOM())" in interactive
    assert "ADD TABLES" not in interactive, "tables are attached at creation with TABLES (...)"
    assert "ALTER INTERACTIVE TABLE ANALYTICS_DB.SERVING.DAILY_INTERACTIVE SUSPEND" in interactive

    app_root = ROOT / "native_app"
    manifest = yaml.safe_load((app_root / "manifest.yml").read_text())
    assert manifest["manifest_version"] == 1
    assert manifest["artifacts"]["default_streamlit"] == "app_public.dashboard"
    assert (app_root / manifest["artifacts"]["setup_script"]).is_file()
    ast.parse((app_root / "streamlit" / "app.py").read_text())
    app_sql = (app_root / "setup.sql").read_text()
    assert "FROM '/streamlit'" in app_sql and "MAIN_FILE = '/app.py'" in app_sql

    install = (ROOT / "chapter19_3_install.sql").read_text()
    assert "REGISTER VERSION V1" in install and "RELEASE CHANNEL DEFAULT" in install
    assert not re.search(r"^ALTER APPLICATION PACKAGE[^;]*ADD VERSION V1\s+USING", install, re.M | re.S), \
        "ADD VERSION ... USING is rejected when release channels are enabled"

    agent_sql = (ROOT / "chapter19_4_agents.sql").read_text()
    spec = yaml.safe_load(agent_sql.split("FROM SPECIFICATION $$", 1)[1].split("$$;", 1)[0])
    names = {tool["tool_spec"]["name"] for tool in spec["tools"]}
    assert names == set(spec["tool_resources"])
    assert "CREATE CORTEX AGENT" not in agent_sql
    assert not re.search(r"GRANT SELECT[^;]*TO ROLE NO_DATA_READER", agent_sql, re.S)
    assert not re.search(r"GRANT SELECT ON TABLE[^;]*PAYMENT_ATTEMPTS\s+TO ROLE BI_READER", agent_sql, re.S), \
        "BI_READER must not receive row-level payment access"

    for client in ("chapter19_2_load_test.py", "chapter19_4_chat_client.py"):
        ast.parse((ROOT / client).read_text())

    skill = (ROOT / "cowork_skill" / "review-payment-performance" / "SKILL.md").read_text()
    front = yaml.safe_load(skill.split("---", 2)[1])
    assert front["name"] == "review-payment-performance" and front["description"]

    if len(sys.argv) > 1:
        manuscript = Path(sys.argv[1]).read_text()
        artifacts = [p.read_text() for p in ROOT.rglob("*")
                     if p.suffix in {".sql", ".yml", ".py"} or p.name == "SKILL.md"]
        excerpts = re.findall(r"```(?:sql|yaml|python|markdown)\n(.*?)\n```", manuscript, re.S)
        for excerpt in excerpts:
            assert any(excerpt in source for source in artifacts), \
                "Unmatched manuscript code excerpt:\n" + excerpt[:200]
        assert len(excerpts) == EXPECTED_EXCERPTS, len(excerpts)
    print("PASS: fixture arithmetic, SQL seed parity, warehouse limits, release channel, "
          "application paths, Python syntax, agent YAML/grants, skill frontmatter")
    if len(sys.argv) > 1:
        print(f"PASS: all {EXPECTED_EXCERPTS} manuscript code excerpts match companion files")
    print("Live Snowflake, BI, Native App, REST client and CoWork validation: NOT RUN")


if __name__ == "__main__":
    main()
