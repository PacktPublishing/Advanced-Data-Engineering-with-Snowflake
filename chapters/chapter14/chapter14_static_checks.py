#!/usr/bin/env python3
"""Offline consistency checks for the Chapter 14 companion directory.

Run before committing changes to chapters/chapter14:

    python3 chapter14_static_checks.py
    python3 chapter14_static_checks.py --manuscript /path/to/Chapter_14_*.md

Checks nothing that needs a Snowflake connection. Exits non-zero on failure.
With --manuscript it also verifies that every fenced ```sql block in the
chapter appears, whitespace-normalized, inside one of the companion scripts
(the text-to-repo alignment contract), that every ```text prompt block appears
in the coco script's comment header, that no companion file name leaks into
the body prose (the Technical Requirements repo pointer and the AGENTS.md
convention name are the only allowed mentions), and that the headings follow
the Packt rules settled in September 2026: sentence case, unnumbered ##,
numbered ### as N.M. If sqlglot is installed, every statement is also parsed
in the Snowflake dialect. chapter14_logic_sim.py, the DuckDB emulation, is the
runtime counterpart of this file.
"""

import argparse
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent

EXPECTED_FILES = [
    "chapter14_0_setup.sql",
    "chapter14_1_star_schema.sql",
    "chapter14_2_scd_patterns.sql",
    "chapter14_3_data_vault.sql",
    "chapter14_4_coco.sql",
    "chapter14_teardown.sql",
    "README.md",
    "AGENTS.md",
    ".cortex/skills/scd-dimension/SKILL.md",
    "chapter14_static_checks.py",
    "chapter14_logic_sim.py",
]

# Every identifier the setup or a section introduces must be reversed by name.
TEARDOWN_MUST_MENTION = [
    "DROP VIEW IF EXISTS gold_db.customers.dim_customers_invariants",
    "UNSET COMMENT",
    "star_transactions",
    "fk_txn_merchant",
    "pk_dim_merchants",
    "pk_fact_transactions NORELY",
    "gold_db.calendar",
    "previous_category",
    "MERCH-CH14-",
    "dim_merchants_before_ch14",
    "CUST-CH14-",
    "CUST-CH12-0007",
    "CUST-CH12-0042",
    "2026-03-01 06:00:00",
    "CH12-SEED",
    "stg_customer_extract",
    "stg_merchant_updates",
    "stg_merchant_reclass",
    "raw_db.crm.customer_history",
    "raw_db.partners.merchant_directory",
    "raw_db.partners",
    "vault_db",
]

# Counts the chapter quotes; each must appear in the script that produces it.
EXPECTED_COUNT_STRINGS = {
    "chapter14_1_star_schema.sql": ["ROWCOUNT => 1095", "MODIFY CONSTRAINT pk_fact_transactions RELY",
                                    "dirty_key EXCEPTION", "rely = 'YES'"],
    "chapter14_2_scd_patterns.sql": ["inserted: 1", "updated: 3", "updated: 2", "inserted: 3",
                                     "duplicate_extract EXCEPTION", "ADD COLUMN IF NOT EXISTS",
                                     "WHEN OTHER THEN", "SQLROWCOUNT", "closed 2, inserted 3"],
    "chapter14_0_setup.sql": ["MERCH-CH14-NEW01", "CUST-CH14-0001", "'electronics'",
                              "MERCH-CH14-ELEC01", "MERCH-CH14-ELEC02",
                              "UPPER(merchant_category) = 'ELECTRONICS'"],
    "chapter14_4_coco.sql": ["'current_count_not_one'", "'overlapping_windows'", "'internal_gap'",
                             "'current_end_not_sentinel'", "'invalid_window'",
                             "COALESCE(COUNT_IF(is_current), 0)", "IS DISTINCT FROM '9999-12-31'"],
    "chapter14_3_data_vault.sql": ["COUNT(DISTINCT UPPER(TRIM(customer_id)))",
                                   "FROM raw_db.crm.customer_history",
                                   "FROM raw_db.partners.merchant_directory"],
}

# Manuscript heading rules (Packt, Chapter 13 round, 2026-09-05). Words that
# keep their own casing inside a sentence-case heading.
HEADING_PROPER = {"TechFlow", "Snowflake", "Snowflake's", "SCD", "Types", "Iceberg", "CoCo", "Data", "Vault",
                  "MERGE", "Type", "Summary", "Technical", "Requirements"}

failures = []
notes = []


def fail(check, detail):
    failures.append(f"{check}: {detail}")


def sql_files():
    return sorted(p for p in HERE.glob("chapter14_*.sql"))


def strip_comments(text):
    return re.sub(r"--[^\n]*", "", text)


def strip_literals(text):
    return re.sub(r"'(?:[^']|'')*'", "''", text)


def normalize(sql):
    """Whitespace-insensitive form used for snippet alignment."""
    return re.sub(r"\s+", " ", sql).strip().lower()


def check_inventory():
    for name in EXPECTED_FILES:
        if not (HERE / name).exists():
            fail("inventory", f"missing {name}")


def check_headers_and_roles():
    for p in sql_files():
        text = p.read_text()
        if not text.lstrip().startswith("-- ====="):
            fail("header", f"{p.name} does not open with the standard comment header")
        body = strip_comments(text)
        first_stmt = body.strip().split(";")[0].strip().upper()
        if first_stmt != "USE ROLE SYSADMIN":
            fail("roles", f"{p.name}: first statement is '{first_stmt}', expected USE ROLE SYSADMIN")
        if "<REPLACE" in body:
            fail("placeholders", f"{p.name} carries a <REPLACE> marker; this chapter should have none")


def check_parens():
    for p in sql_files():
        depth = 0
        for ch in strip_literals(strip_comments(p.read_text())):
            depth += (ch == "(") - (ch == ")")
        if depth:
            fail("parens", f"{p.name} unbalanced by {depth}")


def check_banned_patterns():
    shared = ("gold_db.transactions", "gold_db.customers", "gold_db.merchants", "raw_db.crm")
    for p in sql_files():
        body = strip_comments(p.read_text())
        for m in re.finditer(r"DROP\s+SCHEMA[^;]*CASCADE", body, re.I):
            fail("cascade", f"{p.name}: {m.group(0).strip()}")
        for m in re.finditer(r"DROP\s+(?:SCHEMA|TABLE|VIEW)\s+(?:IF\s+EXISTS\s+)?([a-z_.]+)", body, re.I):
            target = m.group(1).lower()
            if any(target.startswith(s) for s in shared) and "teardown" not in p.name:
                fail("shared-drop", f"{p.name} drops {target}, which lives in a shared schema")
        for m in re.finditer(r"DROP\s+DATABASE\s+(?:IF\s+EXISTS\s+)?([a-z_]+)", body, re.I):
            if m.group(1).lower() != "vault_db":
                fail("database-drop", f"{p.name} drops database {m.group(1)}")
        if re.search(r"UPPER\(\s*rely\s*\)\s*=\s*'TRUE'|rely\s*=\s*'TRUE'", body, re.I):
            fail("rely-literal", f"{p.name} compares TABLE_CONSTRAINTS.rely with 'TRUE'; the column holds 'YES'/'NO'")
        for m in re.finditer(r"CREATE\s+OR\s+REPLACE\s+TABLE\s+([a-z_.]+)", body, re.I):
            target = m.group(1).lower()
            if target in ("gold_db.transactions.fact_transactions",
                          "gold_db.customers.dim_customers",
                          "gold_db.merchants.dim_merchants"):
                fail("shared-replace", f"{p.name} replaces the shared table {target}")


def check_teardown():
    p = HERE / "chapter14_teardown.sql"
    if not p.exists():
        return
    t = p.read_text()
    for token in TEARDOWN_MUST_MENTION:
        if token not in t:
            fail("teardown", f"does not mention {token}")


def check_vault_sources():
    p = HERE / "chapter14_3_data_vault.sql"
    if not p.exists():
        return
    body = strip_comments(p.read_text())
    # The two extracts are built from gold once (block 0a); every loader reads them.
    loaders = body[body.index("MERGE INTO vault_db.rawvault.hub_customer"):]
    for mart in ("gold_db.customers.dim_customers\n", "gold_db.customers.dim_customers ",
                 "gold_db.merchants.dim_merchants"):
        if mart in loaders.split("Section 4 validation set")[0]:
            fail("vault-sources", f"a vault loader reads {mart.strip()} instead of its raw_db extract")


def check_setup():
    p = HERE / "chapter14_0_setup.sql"
    if not p.exists():
        return
    t = p.read_text()
    if "CREATE TABLE IF NOT EXISTS raw_db.partners.dim_merchants_before_ch14" not in t:
        fail("setup", "snapshot must be CREATE TABLE IF NOT EXISTS so re-runs keep the pristine copy")
    if "FROM raw_db.partners.dim_merchants_before_ch14" not in t:
        fail("setup", "fixtures must derive from the snapshot, not the live dim_merchants")
    for exc in ("no_payments", "no_refunds", "no_merchants", "no_seed_customers",
                "movers_not_current", "no_current_view"):
        if f"{exc} EXCEPTION" not in t:
            fail("setup", f"prerequisite guard lacks the {exc} exception (one exception per check)")
    if "merchant_category = 'electronics'" in t:
        fail("setup", "category test must be case-insensitive: UPPER(merchant_category) = 'ELECTRONICS'")


def check_expected_counts():
    for name, tokens in EXPECTED_COUNT_STRINGS.items():
        p = HERE / name
        if not p.exists():
            continue
        t = p.read_text()
        for tok in tokens:
            if tok not in t:
                fail("expected-counts", f"{name} lacks '{tok}'")


def check_sqlglot():
    try:
        import sqlglot
    except ImportError:
        notes.append("sqlglot not installed; dialect parse skipped")
        return
    import logging
    logging.getLogger("sqlglot").setLevel(logging.ERROR)
    for p in sql_files():
        # Literals are blanked first so a ';' inside a COMMENT string cannot
        # split a statement; the parser only needs the syntax around them.
        body = strip_literals(strip_comments(p.read_text()))
        # Split on ; outside $$ blocks; skip Snowflake Scripting blocks entirely.
        parts, buf, in_dollar = [], [], False
        i = 0
        while i < len(body):
            if body.startswith("$$", i):
                in_dollar = not in_dollar
                buf.append("$$")
                i += 2
                continue
            ch = body[i]
            if ch == ";" and not in_dollar:
                parts.append("".join(buf))
                buf = []
            else:
                buf.append(ch)
            i += 1
        if "".join(buf).strip():
            parts.append("".join(buf))
        for stmt in parts:
            s = stmt.strip()
            if not s or "$$" in s:
                continue
            head = s.split()[0].upper()
            if head in ("EXPLAIN", "SHOW", "COMMENT", "EXECUTE"):
                continue  # not covered by the parser's grammar
            if re.match(r"CREATE\s+(OR\s+REPLACE\s+)?ALERT", s, re.I):
                fail("alert", f"{p.name} creates an alert; the scheduled check moved to Chapter 16")
                continue
            try:
                sqlglot.parse_one(s, read="snowflake")
            except Exception as e:  # noqa: BLE001
                fail("sqlglot", f"{p.name}: {str(e).splitlines()[0][:160]} :: {s[:70]!r}")


def check_manuscript_headings(text):
    """## unnumbered and sentence case; ### numbered N.M and sentence case."""
    for line in text.splitlines():
        if line.startswith("#### ") or not line.startswith("#"):
            continue
        if line.startswith("# "):
            continue  # chapter title keeps its own case
        level, heading = line.split(" ", 1)
        if level == "##":
            if re.match(r"\d", heading):
                fail("headings", f"## heading carries a number: {heading!r}")
            words = heading.split()
        elif level == "###":
            m = re.match(r"(\d+\.\d+)\s+(.*)", heading)
            if not m:
                fail("headings", f"### heading lacks the N.M number: {heading!r}")
                continue
            words = m.group(2).split()
        else:
            continue
        for w in words[1:]:
            bare = w.strip(",:")
            if bare and bare[0].isupper() and bare not in HEADING_PROPER and not bare.isupper() \
                    and not re.match(r"\d", bare):
                fail("headings", f"Title Case word {bare!r} in heading {heading!r}")
        if any(ch in heading for ch in ":\u2014"):
            fail("headings", f"colon or em dash in heading {heading!r}")


def check_manuscript_file_names(text):
    """Companion file names stay out of body prose; refer to scripts by role."""
    body = re.sub(r"```.*?```", "", text, flags=re.S)
    for m in re.finditer(r"`?(chapter14_[A-Za-z0-9_]+\.(?:sql|py|md))`?", body):
        fail("file-names", f"companion file name in prose: {m.group(1)}")
    for m in re.finditer(r"`([A-Za-z0-9_\-]+\.(?:sql|py))`", body):
        fail("file-names", f"script name in prose: {m.group(1)}")


def check_manuscript(path):
    text = pathlib.Path(path).read_text()
    check_manuscript_headings(text)
    check_manuscript_file_names(text)
    # Two corpora: the raw files, and the files with '-- ' comment prefixes
    # removed, so a chapter block that a script keeps as a named comment block
    # (the worksheet pair in the SCD script, per the runnable-SQL-only rule)
    # still aligns verbatim.
    corpus = normalize("\n".join(p.read_text() for p in sql_files()))
    uncommented_corpus = normalize("\n".join(
        re.sub(r"^\s*--\s?", "", p.read_text(), flags=re.M) for p in sql_files()))
    comment_corpus = normalize("\n".join(
        re.sub(r"^\s*--\s?", "", line)
        for p in sql_files()
        for line in p.read_text().splitlines() if line.lstrip().startswith("--")))
    # The chapter refers to scripts by role, so the only file names allowed are
    # the repo URL (Technical Requirements) and AGENTS.md. Anything else cited
    # by name is a rule violation, reported by check_manuscript_file_names.
    cited = set(re.findall(r"`([A-Za-z0-9_\-]+\.(?:sql|md|py))`", text))
    for name in sorted(cited - {"AGENTS.md"}):
        notes.append(f"manuscript cites {name} by name (allowed only for AGENTS.md)")
    # Every section script must still be reachable by role from the prose.
    roles = {
        "chapter14_0_setup.sql": "companion setup script",
        "chapter14_1_star_schema.sql": "companion star schema script",
        "chapter14_2_scd_patterns.sql": "companion SCD script",
        "chapter14_3_data_vault.sql": "companion Data Vault script",
        "chapter14_4_coco.sql": "companion CoCo script",
        "chapter14_teardown.sql": "companion teardown script",
    }
    for name, role in roles.items():
        if role not in text:
            fail("role-pointers", f"manuscript never points at the {role} ({name})")
    blocks = re.findall(r"```(sql|text)\n(.*?)```", text, re.S)
    n_sql = n_text = 0
    for lang, block in blocks:
        norm = normalize(block)
        if lang == "sql":
            n_sql += 1
            if norm not in corpus and norm not in uncommented_corpus:
                first = block.strip().splitlines()[0][:60]
                fail("snippet-alignment", f"manuscript SQL block not found verbatim in scripts: {first!r}")
        else:
            n_text += 1
            if norm not in comment_corpus:
                first = block.strip().splitlines()[0][:60]
                fail("prompt-alignment", f"manuscript prompt not found in a script header: {first!r}")
    notes.append(f"manuscript: {n_sql} sql blocks and {n_text} prompt blocks checked")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manuscript", help="path to Chapter_14_*.md")
    args = ap.parse_args()

    check_inventory()
    check_headers_and_roles()
    check_parens()
    check_banned_patterns()
    check_teardown()
    check_setup()
    check_vault_sources()
    check_expected_counts()
    check_sqlglot()
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
