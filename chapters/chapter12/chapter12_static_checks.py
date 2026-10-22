#!/usr/bin/env python3
"""Offline consistency checks for the Chapter 12 companion directory.

Run before committing changes to chapters/chapter12:

    python3 chapter12_static_checks.py

Checks nothing that needs a Snowflake connection. Exits non-zero on failure.
Optionally cross-checks the manuscript for phantom paths:

    python3 chapter12_static_checks.py --manuscript /path/to/Chapter_12_*.md
"""

import argparse
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent

EXPECTED_FILES = [
    "chapter12_0_setup.sql",
    "chapter12_1_semantic_layer.sql",
    "chapter12_2_create_view.sql",
    "chapter12_3_query_view.sql",
    "chapter12_4_agent_backing.sql",
    "chapter12_5_coco.sql",
    "chapter12_teardown.sql",
    "techflow_revenue.yaml",
    "README.md",
    "AGENTS.md",
    "chapter12_static_checks.py",
]

# The four physical objects the semantic view maps, on the REAL gold layer.
MODEL_OBJECTS = [
    "gold_db.transactions.fact_transactions",
    "gold_db.transactions.fact_refunds",
    "gold_db.customers.dim_customers_current",
    "gold_db.merchants.dim_merchants",
]

CLAUSE_ORDER = [
    "TABLES", "RELATIONSHIPS", "VARIABLES", "FACTS", "DIMENSIONS",
    "METRICS", "COMMENT", "AI_SQL_GENERATION", "AI_VERIFIED_QUERIES",
]

failures = []
notes = []


def fail(check, detail):
    failures.append(f"{check}: {detail}")


def sql_files():
    return sorted(p for p in HERE.glob("chapter12_*.sql"))


def check_inventory():
    for name in EXPECTED_FILES:
        if not (HERE / name).exists():
            fail("inventory", f"missing {name}")
    stale = {"autopilot_context.csv", "chapter12_setup.sql", "chapter12_assertions.sql",
             "promote_semantic_view.sql", "validate_v1.sql", "validate_v2.sql",
             "validate_final.sql", "techflow_revenue_v1.sql", "techflow_revenue_v2.sql",
             "techflow_revenue_v3.sql", "techflow_revenue_final.sql"}
    for name in stale:
        if (HERE / name).exists():
            fail("inventory", f"{name} belongs to the abandoned copied-star design")


def check_no_chapter_owned_star():
    """The single most important regression: the view must not be rebuilt over
    a duplicate star inside gold_db.semantic."""
    banned = re.compile(r"gold_db\.semantic\.(fact_|dim_)", re.I)
    for p in sql_files() + [HERE / "AGENTS.md", HERE / "README.md"]:
        if not p.exists():
            continue
        for n, line in enumerate(p.read_text().splitlines(), 1):
            if banned.search(line if p.suffix != ".sql" else strip_comments(line)):
                fail("copied-star", f"{p.name}:{n} references a table in gold_db.semantic")


def check_model_objects():
    create = (HERE / "chapter12_2_create_view.sql")
    if not create.exists():
        return
    text = create.read_text()
    for obj in MODEL_OBJECTS:
        if obj not in text:
            fail("model", f"chapter12_2_create_view.sql never references {obj}")
    for rel in ("txn_to_customer", "txn_to_merchant", "refund_to_txn"):
        if rel not in text:
            fail("model", f"relationship {rel} missing")
    if "ZEROIFNULL" not in text:
        fail("model", "no ZEROIFNULL: the cross-grain refund fact nets to null without it")
    if "PRIVATE refunds.refund_amount AS refund_amount" not in text:
        fail("model", "cross-table SUM needs PRIVATE refunds.refund_amount declared as a fact first")


def _top_level_clause_order(stmt):
    """CLAUSE_ORDER keywords in appearance order at paren-depth 0.

    Nested COMMENT / METRICS / DIMENSIONS (inside TABLES, AI_VERIFIED_QUERIES,
    etc.) sit at depth > 0 and must not count. String literals are blanked so
    parentheses and keywords inside quotes cannot shift depth or order.
    """
    cleaned = re.sub(r"'(?:[^']|'')*'", "''", stmt)
    clause_re = re.compile(
        r"[()]|\b(" + "|".join(CLAUSE_ORDER) + r")\b", re.I)
    depth = 0
    seen = []
    for m in clause_re.finditer(cleaned):
        tok = m.group(0)
        if tok == "(":
            depth += 1
        elif tok == ")":
            depth = max(0, depth - 1)
        elif depth == 0:
            seen.append(tok.upper())
    return seen


def check_clause_order():
    stmt_re = re.compile(
        r"CREATE\s+OR\s+(?:REPLACE|ALTER)\s+SEMANTIC\s+VIEW.*?;", re.S | re.I)
    for p in sql_files():
        for stmt in stmt_re.findall(p.read_text()):
            seen = _top_level_clause_order(stmt)
            expected = [c for c in CLAUSE_ORDER if c in seen]
            if seen != expected:
                fail("clause-order", f"{p.name}: {seen}")


# COMMENT takes '=' on every element, including variables. The documented
# variableDef grammar is `[ COMMENT '<description>' ]` with no equals sign;
# Snowflake 10.28.101 rejects the bare form. Keep this True.
VARIABLE_COMMENT_TAKES_EQUALS = True


def blank_literals(text):
    """Blank the inside of every single-quoted literal, preserving length and
    newlines so character offsets and line numbers still line up.

    Deliberately separate from _top_level_clause_order's regex blanking: that
    one only needs clause order, this one needs positions for error messages.
    """
    out = list(text)
    i, n, in_str = 0, len(text), False
    while i < n:
        c = text[i]
        if not in_str:
            if c == "'":
                in_str = True
        elif c == "'":
            if i + 1 < n and text[i + 1] == "'":   # doubled '' escape
                out[i] = out[i + 1] = "x"
                i += 2
                continue
            in_str = False
        elif c != "\n":
            out[i] = "x"
        i += 1
    return "".join(out)


def comment_clauses(stmt):
    """Yield (enclosing_top_level_clause, has_equals, offset) per COMMENT.

    A COMMENT nested inside VARIABLES(...) is a variableDef comment; one nested
    inside TABLES / FACTS / DIMENSIONS / METRICS belongs to an element; one at
    paren-depth 0 is the view's own.
    """
    cleaned = blank_literals(stmt)
    token = re.compile(
        r"[()]|\bCOMMENT\b\s*(=)?|\b(" + "|".join(CLAUSE_ORDER) + r")\b", re.I)
    depth, current = 0, None
    for m in token.finditer(cleaned):
        tok = m.group(0)
        if tok == "(":
            depth += 1
        elif tok == ")":
            depth = max(0, depth - 1)
        elif tok.upper().startswith("COMMENT"):
            yield (current if depth else None, "=" in tok, m.start())
        elif depth == 0:
            current = m.group(0).upper()


def check_comment_equals():
    """COMMENT = '...' on every element, including variables."""
    stmt_re = re.compile(
        r"CREATE\s+OR\s+(?:REPLACE|ALTER)\s+SEMANTIC\s+VIEW.*?;", re.S | re.I)
    for p in sql_files():
        text = p.read_text()
        for stmt in stmt_re.findall(text):
            base = text.index(stmt)
            for clause, has_eq, off in comment_clauses(stmt):
                line = text.count("\n", 0, base + off) + 1
                in_var = clause == "VARIABLES"
                want = VARIABLE_COMMENT_TAKES_EQUALS if in_var else True
                where = "a variable" if in_var else (clause or "the view")
                if has_eq and not want:
                    fail("comment-equals",
                         f"{p.name}:{line} COMMENT on {where} should omit '=' "
                         f"(variableDef grammar)")
                elif not has_eq and want:
                    fail("comment-equals",
                         f"{p.name}:{line} COMMENT on {where} needs '='")


def check_deploy_verbs():
    create = HERE / "chapter12_2_create_view.sql"
    if create.exists():
        t = create.read_text()
        if "CREATE OR REPLACE SEMANTIC VIEW" not in t:
            fail("verbs", "stage 1 should create the object with CREATE OR REPLACE")
        if "CREATE OR ALTER SEMANTIC VIEW" not in t:
            fail("verbs", "stage 2 should use CREATE OR ALTER")
    for name in ("chapter12_4_agent_backing.sql", "chapter12_5_coco.sql"):
        p = HERE / name
        if p.exists() and "CREATE OR REPLACE SEMANTIC VIEW" in p.read_text():
            fail("verbs", f"{name} must use CREATE OR ALTER to preserve grants")


def strip_comments(text):
    """Drop -- comments so prose about a banned pattern is not a finding."""
    return re.sub(r"--[^\n]*", "", text)


def check_teardown():
    p = HERE / "chapter12_teardown.sql"
    if not p.exists():
        return
    t = p.read_text()
    if re.search(r"DROP\s+SCHEMA[^\n;]*CASCADE", strip_comments(t), re.I):
        fail("teardown", "DROP SCHEMA ... CASCADE is banned on shared schemas")
    if "TXN-CH12-" not in t:
        fail("teardown", "does not delete the TXN-CH12- rows from fact_transactions")
    if "CH12-SEED" not in t or "CH12-BACKFILL" not in t:
        fail("teardown", "does not delete the tagged dim_customers rows")


def check_setup_markers():
    p = HERE / "chapter12_0_setup.sql"
    if not p.exists():
        return
    t = p.read_text()
    if "'TXN-CH12-' || seq" not in t:
        fail("markers", "setup does not prefix inserted transaction_id with TXN-CH12-")
    if t.count("DELETE FROM") < 2:
        fail("markers", "setup is not re-runnable: tagged rows are not deleted first")
    if "USE ROLE SYSADMIN;" not in t:
        fail("roles", "setup does not open with USE ROLE SYSADMIN;")


def check_autopilot_gone():
    for p in HERE.glob("*"):
        if p.is_file() and p.suffix in {".sql", ".md", ".yaml", ".csv"}:
            body = p.read_text()
            if p.suffix == ".sql":
                body = strip_comments(body)
            if re.search(r"autopilot", body, re.I):
                fail("autopilot", f"{p.name} still references Autopilot (cut from the chapter)")


def check_parens():
    for p in sql_files():
        depth = 0
        for ch in re.sub(r"--[^\n]*", "", p.read_text()):
            depth += (ch == "(") - (ch == ")")
        if depth:
            fail("parens", f"{p.name} unbalanced by {depth}")


def check_manuscript(path):
    text = pathlib.Path(path).read_text()
    cited = set(re.findall(r"`([A-Za-z0-9_\-]+\.(?:sql|yaml|md|csv|py))`", text))
    for name in sorted(cited):
        if not (HERE / name).exists():
            fail("path-alignment", f"manuscript cites {name}, which does not exist")
    for p in sql_files():
        if p.name not in cited:
            notes.append(f"{p.name} is not cited by name in the manuscript")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manuscript", help="path to Chapter_12_*.md")
    args = ap.parse_args()

    check_inventory()
    check_no_chapter_owned_star()
    check_model_objects()
    check_clause_order()
    check_comment_equals()
    check_deploy_verbs()
    check_teardown()
    check_setup_markers()
    check_autopilot_gone()
    check_parens()
    if args.manuscript:
        check_manuscript(args.manuscript)

    for n in notes:
        print(f"note: {n}")
    if failures:
        print(f"\n{len(failures)} FAILURE(S):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
