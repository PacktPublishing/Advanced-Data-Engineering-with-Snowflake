#!/usr/bin/env python3
"""Offline logic test for the Chapter 14 companion scripts.

    pip install duckdb sqlglot
    python3 chapter14_logic_sim.py

Emulates the Chapter 5 + Chapter 12 gold layer in DuckDB at one tenth of the
published fixture size (5,024 payments instead of 50,024), then executes the
relational statements from this directory's chapter14_*.sql files (transpiled
Snowflake -> DuckDB with a handful of shims for functions DuckDB lacks),
asserting the counts the manuscript quotes at that scale, that every loader
is idempotent, that the invariants view catches each kind of broken row, and
that the teardown restores both shared dimensions to their baseline on every
column.

Tested scope, stated precisely:
  - DDL, DML, views, and validation queries run as written (shimmed names).
  - Snowflake Scripting blocks are skipped as blocks; the conditions their
    guards test are re-evaluated in Python, and the DML inside the Type 2
    blocks is extracted and run directly (the rollback demo as a DuckDB
    transaction that is rolled back, the executable pair twice).
  - RELY metadata is emulated: a TABLE_CONSTRAINTS stand-in holds the
    documented 'YES' literal so the validation query's predicate runs.
  - NOT covered, Snowflake only: RELY and join elimination, EXPLAIN,
    COMMENT ON and UNSET COMMENT, the alert and ALERT_HISTORY, and the
    Scripting exception paths. Those are verified only by a live run.
"""
import pathlib
import re
import sys

import duckdb
import sqlglot

CH14 = pathlib.Path(__file__).resolve().parent
con = duckdb.connect()
skipped, ran = [], 0


def statements(sql_text):
    """Literal-aware split on ';' outside $$ blocks, comments removed."""
    body = re.sub(r"--[^\n]*", "", sql_text)
    parts, buf, in_dollar, in_str, i = [], [], False, False, 0
    while i < len(body):
        if not in_str and body.startswith("$$", i):
            in_dollar = not in_dollar
            buf.append("$$")
            i += 2
            continue
        ch = body[i]
        if ch == "'" and not in_dollar:
            in_str = not in_str
        if ch == ";" and not in_dollar and not in_str:
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
        i += 1
    if "".join(buf).strip():
        parts.append("".join(buf))
    return [s.strip() for s in parts if s.strip()]


# ----------------------------------------------------------------------------
# Emulated gold layer (shapes from chapter5_1, chapter5_3, chapter12_0)
# ----------------------------------------------------------------------------
con.execute("""
CREATE SCHEMA gold_db_transactions; CREATE SCHEMA gold_db_customers;
CREATE SCHEMA gold_db_merchants;    CREATE SCHEMA raw_db_crm;
CREATE SCHEMA sim_meta;
-- Stand-in for INFORMATION_SCHEMA.TABLE_CONSTRAINTS after section 2 declares
-- its keys: Snowflake stores RELY there as the strings YES / NO (BCR-1902).
CREATE TABLE sim_meta.table_constraints (
    table_schema VARCHAR, table_name VARCHAR, constraint_name VARCHAR,
    constraint_type VARCHAR, rely VARCHAR);
INSERT INTO sim_meta.table_constraints VALUES
    ('TRANSACTIONS', 'FACT_TRANSACTIONS', 'PK_FACT_TRANSACTIONS', 'PRIMARY KEY', 'YES'),
    ('MERCHANTS', 'DIM_MERCHANTS', 'PK_DIM_MERCHANTS', 'PRIMARY KEY', 'YES'),
    ('CALENDAR', 'DIM_DATE', 'PK_DIM_DATE', 'PRIMARY KEY', 'YES'),
    ('TRANSACTIONS', 'FACT_TRANSACTIONS', 'FK_TXN_MERCHANT', 'FOREIGN KEY', 'YES');
CREATE MACRO sha2(x) AS sha256(x);
CREATE MACRO sha2_binary(x, n) AS sha256(x)::BLOB;
CREATE MACRO nvl(a, b) AS coalesce(a, b);
CREATE MACRO iff(c, a, b) AS CASE WHEN c THEN a ELSE b END;
CREATE MACRO dayofweekiso(d) AS isodow(d);
CREATE MACRO dateadd(part, n, ts) AS
    CASE part WHEN 'day' THEN ts + to_days(n::INT)
              WHEN 'month' THEN ts + to_months(n::INT)
              WHEN 'minute' THEN ts + to_minutes(n::INT) END;
""")
# Snowflake three-part names -> DuckDB schema_table via underscore joining.
NAME_MAP = {
    "gold_db.calendar.key_tests_tmp": "key_tests_tmp",   # temp table: no schema in DuckDB
    "gold_db.information_schema.table_constraints": "sim_meta.table_constraints",
    "gold_db.transactions.": "gold_db_transactions.",
    "gold_db.customers.": "gold_db_customers.",
    "gold_db.merchants.": "gold_db_merchants.",
    "gold_db.calendar.": "gold_db_calendar.",
    "gold_db.information_schema.": "information_schema.",
    "raw_db.crm.": "raw_db_crm.",
    "raw_db.partners.": "raw_db_partners.",
    "vault_db.rawvault.": "vault_db_rawvault.",
    "vault_db.marts.": "vault_db_marts.",
}

con.execute("""
CREATE TABLE gold_db_transactions.fact_transactions (
    transaction_id VARCHAR NOT NULL, customer_id VARCHAR NOT NULL,
    merchant_id VARCHAR NOT NULL, amount DECIMAL(12,2) NOT NULL,
    currency VARCHAR DEFAULT 'USD', transaction_ts TIMESTAMP NOT NULL,
    category VARCHAR, channel VARCHAR, status VARCHAR DEFAULT 'COMPLETED',
    risk_score DECIMAL(5,2), ingested_at TIMESTAMP DEFAULT current_timestamp,
    PRIMARY KEY (transaction_id));
CREATE SEQUENCE customer_key_seq;
CREATE TABLE gold_db_customers.dim_customers (
    customer_key BIGINT DEFAULT nextval('customer_key_seq'),
    customer_id VARCHAR NOT NULL, customer_name VARCHAR, email VARCHAR,
    address_line1 VARCHAR, city VARCHAR, state VARCHAR, postal_code VARCHAR,
    effective_from TIMESTAMP NOT NULL,
    effective_to TIMESTAMP DEFAULT TIMESTAMP '9999-12-31',
    is_current BOOLEAN DEFAULT TRUE, record_hash VARCHAR NOT NULL);
""")
# Chapter 5 style rows: 24 payments minutes/days before "now" (2026-08-28),
# customers C1001-C1003 loaded into the dimension AFTER their payments.
con.execute("""
INSERT INTO gold_db_transactions.fact_transactions
    (transaction_id, customer_id, merchant_id, amount, transaction_ts, category, channel, status, risk_score)
SELECT 'TXN-CH5-' || i,
       CASE WHEN i <= 5 THEN 'C100' || (1 + i % 3) ELSE 'CUST_' || (i % 9) END,
       CASE i % 7 WHEN 0 THEN 'MERCH_ELEC_1' WHEN 1 THEN 'MERCH_ELEC_2' WHEN 2 THEN 'MERCH_GAP'
                  WHEN 3 THEN 'MERCH_GROC_1' WHEN 4 THEN 'MERCH_GROC_2' WHEN 5 THEN 'MERCH_GROC_3'
                  ELSE 'MERCH_TRVL_1' END,
       10 + i, TIMESTAMP '2026-08-28 10:00:00' - to_minutes(i),
       CASE i % 7 WHEN 0 THEN 'ELECTRONICS' WHEN 1 THEN 'ELECTRONICS' WHEN 6 THEN 'TRAVEL' ELSE 'GROCERIES' END,
       'WEB', 'COMPLETED', 40
FROM range(1, 25) t(i);
-- Chapter 5 SCD load happened later than the payments.
INSERT INTO gold_db_customers.dim_customers
    (customer_id, customer_name, email, address_line1, city, state, postal_code, effective_from, record_hash)
SELECT 'C100' || i, 'Customer ' || i, 'c' || i || '@x.com', i || ' Main', 'Austin', 'TX', '78701',
       TIMESTAMP '2026-08-28 12:00:00',
       sha256(concat_ws('|', 'Customer ' || i, 'c' || i || '@x.com', i || ' Main', 'Austin', 'TX', '78701'))
FROM range(1, 4) t(i);
""")
# Chapter 12 seed: 500 customers tagged CH12-SEED, 50,000 -> 5,000 payments here.
con.execute("""
INSERT INTO gold_db_customers.dim_customers
    (customer_id, customer_name, email, address_line1, city, state, postal_code, effective_from, effective_to, is_current, record_hash)
SELECT 'CUST-CH12-' || lpad(seq::VARCHAR, 4, '0'), 'Name ' || seq, 'customer' || lpad(seq::VARCHAR, 4, '0') || '@example.com',
       (100 + seq) || ' Main St',
       (['Austin','Denver','Raleigh','Boise','Madison','Tempe','Savannah','Portland','Buffalo','Fresno'])[seq % 10 + 1],
       (['TX','CO','NC','ID','WI','AZ','GA','OR','NY','CA'])[seq % 10 + 1],
       lpad((seq * 37 % 100000)::VARCHAR, 5, '0'),
       TIMESTAMP '2025-01-01', TIMESTAMP '9999-12-31', TRUE, 'CH12-SEED'
FROM range(500) t(seq);
INSERT INTO gold_db_transactions.fact_transactions
    (transaction_id, transaction_ts, status, customer_id, merchant_id, amount, currency, category, channel, risk_score, ingested_at)
SELECT 'TXN-CH12-' || seq,
       TIMESTAMP '2025-01-01' + to_minutes((seq * 7919) % 786240),
       CASE WHEN seq % 100 < 88 THEN 'COMPLETED' WHEN seq % 100 < 91 THEN 'REFUNDED' WHEN seq % 100 < 96 THEN 'FAILED' ELSE 'PENDING' END,
       'CUST-CH12-' || lpad(((seq * 31) % 500)::VARCHAR, 4, '0'),
       'MERCH-CH12-' || lpad((seq % 40)::VARCHAR, 2, '0'),
       round(5 + (seq * 13 % 14500) / 100.0, 2), 'USD',
       (['retail','travel','dining','software','streaming','gaming','groceries','fitness'])[(seq % 40) % 8 + 1],
       (['mobile','web','POS','API'])[seq % 4 + 1], seq % 101, TIMESTAMP '2026-07-01'
FROM range(5000) t(seq);
-- Chapter 12 backfill for Chapter 5 customers never loaded into the dimension.
INSERT INTO gold_db_customers.dim_customers
    (customer_id, customer_name, email, address_line1, city, state, postal_code, effective_from, effective_to, is_current, record_hash)
SELECT DISTINCT f.customer_id, 'Unmodelled Chapter 5 customer', NULL, NULL, NULL, 'TX', NULL,
       TIMESTAMP '2025-01-01', TIMESTAMP '9999-12-31', TRUE, 'CH12-BACKFILL'
FROM gold_db_transactions.fact_transactions f
WHERE NOT EXISTS (SELECT 1 FROM gold_db_customers.dim_customers d WHERE d.customer_id = f.customer_id AND d.is_current);
CREATE VIEW gold_db_customers.dim_customers_current AS
SELECT customer_id, customer_name, email, address_line1, city, state, postal_code
FROM gold_db_customers.dim_customers WHERE is_current = TRUE;
CREATE TABLE gold_db_merchants.dim_merchants (
    merchant_id VARCHAR NOT NULL, merchant_name VARCHAR, merchant_category VARCHAR, merchant_city VARCHAR);
INSERT INTO gold_db_merchants.dim_merchants
SELECT merchant_id, merchant_id, lower(coalesce(max(category), 'retail')),
       (['Austin','Denver','Raleigh','Boise','Madison','Tempe','Savannah','Portland','Buffalo','Fresno'])[(hash(merchant_id) % 10 + 1)::BIGINT]
FROM gold_db_transactions.fact_transactions GROUP BY merchant_id;
CREATE TABLE gold_db_transactions.fact_refunds (
    refund_id VARCHAR NOT NULL, transaction_id VARCHAR NOT NULL, refund_amount DECIMAL(12,2) NOT NULL,
    refund_ts TIMESTAMP NOT NULL, refund_reason VARCHAR);
INSERT INTO gold_db_transactions.fact_refunds
SELECT 'RFD-' || transaction_id, transaction_id, round(amount * 0.6, 2), transaction_ts + to_days(3), 'customer request'
FROM gold_db_transactions.fact_transactions WHERE status = 'REFUNDED';
""")

baseline = {
    "dim_merchants": con.execute("SELECT * FROM gold_db_merchants.dim_merchants ORDER BY 1").fetchall(),
    "dim_customers": con.execute("SELECT * FROM gold_db_customers.dim_customers ORDER BY customer_key").fetchall(),
}
fact_rows = con.execute("SELECT COUNT(*) FROM gold_db_transactions.fact_transactions").fetchone()[0]
merchants = con.execute("SELECT COUNT(*) FROM gold_db_merchants.dim_merchants").fetchone()[0]
print(f"emulated gold layer: {fact_rows} payments, {merchants} merchants")

SKIP_HEADS = ("EXPLAIN", "SHOW", "COMMENT", "EXECUTE", "USE", "SET")   # SET: Snowflake session variable


def shim(stmt):
    s = stmt
    for k, v in NAME_MAP.items():
        s = s.replace(k, v)
    s = re.sub(r"CREATE\s+DATABASE\s+IF\s+NOT\s+EXISTS\s+\w+(\s+COMMENT\s*=\s*'[^']*')?", "SELECT 1", s, flags=re.I)
    s = re.sub(r"CREATE\s+SCHEMA\s+IF\s+NOT\s+EXISTS\s+(\w+)\.(\w+)(\s+COMMENT\s*=\s*'[^']*')?",
               lambda m: f"CREATE SCHEMA IF NOT EXISTS {m.group(1)}_{m.group(2)}", s, flags=re.I)
    s = re.sub(r"\n\s*COMMENT\s*=\s*'[^']*'\s*\n", "\n", s)          # CTAS COMMENT clause
    # DuckDB's DROP SCHEMA refuses a non-empty schema (its RESTRICT default), so
    # the emulation also proves the named drops above it left nothing behind.
    s = re.sub(r"DROP\s+SCHEMA\s+IF\s+EXISTS\s+(\w+)\.(\w+)\s*(RESTRICT)?",
               lambda m: f"DROP SCHEMA IF EXISTS {m.group(1)}_{m.group(2)}", s, flags=re.I)
    s = re.sub(r"FROM\s+TABLE\(GENERATOR\(ROWCOUNT\s*=>\s*(\d+)\)\)", r"FROM range(\1) g(seq8)", s, flags=re.I)
    s = s.replace("SEQ8()", "seq8")
    s = re.sub(r"::TIMESTAMP_NTZ", "::TIMESTAMP", s)
    s = re.sub(r"\bTIMESTAMP_NTZ\b", "TIMESTAMP", s)
    s = re.sub(r"\bBINARY\(32\)", "BLOB", s)
    s = re.sub(r"\bVARCHAR\b(?!\()", "VARCHAR", s)
    s = re.sub(r"UPDATE SET tgt\.", "UPDATE SET ", s)
    s = re.sub(r",\s*\n\s*tgt\.", ",\n ", s)                       # continued SET lines
    s = s.replace("vault_db_rawvault.hk(", "hk(")
    s = re.sub(r"COUNT_IF\(", "count_if(", s, flags=re.I)
    # The alert test's session variable (set by a skipped SET statement) has no
    # DuckDB counterpart; the log query it filters is empty here anyway.
    s = s.replace("$ch14_alert_test_start", "TIMESTAMP '1970-01-01'")
    return s


def run(stmt, label):
    global ran
    head = stmt.split()[0].upper()
    if re.match(r"CREATE\s+OR\s+REPLACE\s+FUNCTION", stmt, re.I):
        con.execute("CREATE OR REPLACE MACRO hk(k) AS sha256(upper(trim(k)))::BLOB")
        ran += 1
        return None
    if head in SKIP_HEADS or "$$" in stmt or re.search(r"\bALERT\b", stmt, re.I) \
            or re.search(r"\b(ADD|DROP|MODIFY)\s+CONSTRAINT|NORELY|RELY;|DROP\s+DATABASE", stmt, re.I) \
            or "RESULT_SCAN" in stmt \
            or re.search(r"UNSET\s+COMMENT", stmt, re.I):
        skipped.append(f"{label}: {stmt.split(chr(10))[0][:70]}")
        return None
    s = shim(stmt)
    if re.match(r"ALTER\s+TABLE\s+\S+\s+ADD\s+COLUMN", s, re.I):
        # DuckDB adds one column per statement.
        m = re.match(r"ALTER\s+TABLE\s+(\S+)\s+ADD\s+COLUMN\s+(.*)", s, re.S | re.I)
        for col in re.split(r",\s*\n", m.group(2)):
            con.execute(f"ALTER TABLE {m.group(1)} ADD COLUMN {col.strip()}")
        ran += 1
        return None
    if re.match(r"ALTER\s+TABLE\s+\S+\s+DROP\s+COLUMN", s, re.I):
        m = re.match(r"ALTER\s+TABLE\s+(\S+)\s+DROP\s+COLUMN\s+IF\s+EXISTS\s+(.*)", s, re.S | re.I)
        for col in m.group(2).split(","):
            con.execute(f"ALTER TABLE {m.group(1)} DROP COLUMN IF EXISTS {col.strip()}")
        ran += 1
        return None
    if re.match(r"CREATE\s+OR\s+REPLACE\s+FUNCTION", s, re.I):
        con.execute("CREATE OR REPLACE MACRO hk(k) AS sha256(upper(trim(k)))::BLOB")
        ran += 1
        return None
    try:
        sql = sqlglot.transpile(s, read="snowflake", write="duckdb")[0]
    except Exception:
        sql = s
    sql = sql.replace("STRPTIME", "STRPTIME")  # no-op placeholder for clarity
    cur = con.execute(sql)
    ran += 1
    try:
        return cur.fetchall()
    except Exception:
        return None


def run_file(name, capture=(), inline=()):
    """Run a file in order. A $$ block containing a needle from `inline` has its
    DML run in place, so a guarded Scripting block is emulated, not skipped."""
    out = {}
    for i, st in enumerate(statements((CH14 / name).read_text())):
        if inline and "$$" in st and any(n in st for n in inline):
            body = st[st.index("$$") + 2: st.rindex("$$")]
            for inner in (x.strip() for x in body.split(";") if x.strip()):
                if re.match(r"(MERGE|INSERT|UPDATE|DELETE|DROP)\b", inner, re.I):
                    run(inner, f"{name}#{i} block")
            continue
        res = run(st, f"{name}#{i}")
        for key, needle in capture:
            if needle in st and res is not None:
                out[key] = res
    return out


def block_statements(name, needle):
    """Statements inside the $$ Scripting block that contains `needle`."""
    for st in statements((CH14 / name).read_text()):
        if "$$" in st and needle in st:
            body = st[st.index("$$") + 2: st.rindex("$$")]
            inner = [s.strip() for s in body.split(";") if s.strip()]
            return [s for s in inner if re.match(r"(MERGE|INSERT|UPDATE|DELETE)\b", s, re.I)]
    raise AssertionError(f"no $$ block containing {needle!r} in {name}")


def rowcount_of(stmt_needle, name):
    """Run a single statement from a file by needle and return DuckDB's change count."""
    for st in statements((CH14 / name).read_text()):
        if stmt_needle in st:
            res = run(st, name)
            return res


# --- setup ------------------------------------------------------------------
# The prerequisite guard is a Snowflake Scripting block; emulate its conditions.
assert merchants > 0 and con.execute(
    "SELECT COUNT(*) FROM gold_db_customers.dim_customers WHERE record_hash='CH12-SEED' AND is_current").fetchone()[0] >= 50
electronics_before = con.execute("SELECT COUNT(*) FROM gold_db_merchants.dim_merchants WHERE upper(merchant_category)='ELECTRONICS'").fetchone()[0]
assert electronics_before == 2, electronics_before   # the Chapter 5 pair, lower-cased by the Chapter 12 build
assert con.execute("SELECT COUNT(*) FROM gold_db_customers.dim_customers WHERE customer_id IN ('CUST-CH12-0007','CUST-CH12-0042') "
                   "AND record_hash='CH12-SEED' AND is_current").fetchone()[0] == 2
assert con.execute("SELECT COUNT(*) FROM information_schema.views WHERE table_schema='gold_db_customers' "
                   "AND table_name='dim_customers_current'").fetchone()[0] == 1
con.execute("CREATE SCHEMA IF NOT EXISTS raw_db_partners")
out = run_file("chapter14_0_setup.sql", [("fixtures", "'stg_merchant_updates'  AS fixture")])
fixtures = dict(out["fixtures"])
assert fixtures == {"stg_merchant_updates": 4, "stg_customer_extract": 3, "stg_merchant_reclass": 2,
                    "electronics merchants in dim_merchants": 2}, fixtures
assert con.execute("SELECT COUNT(*) FROM gold_db_merchants.dim_merchants WHERE merchant_id LIKE 'MERCH-CH14-ELEC%'").fetchone()[0] == 0, \
    "setup added its own electronics pair although the Chapter 5 pair is present"
print("setup fixtures:", fixtures, "(no chapter-owned electronics pair needed)")

# --- section 2 ---------------------------------------------------------------
con.execute("CREATE SCHEMA IF NOT EXISTS gold_db_calendar")
out = run_file("chapter14_1_star_schema.sql", [
    ("span", "MIN(date_day) AS first_day"),
    ("keys", "SELECT * FROM gold_db.calendar.key_tests_tmp"),
    ("counts", "AS star_transactions_rows"),
    ("star", "AS captured_amount\nFROM gold_db.transactions.star_transactions"),
    ("rely", "constraint_name, constraint_type, rely"),
    ("validation", "'calendar_days'  AS check_name"),
])
assert len(out["rely"]) == 4 and all(r[-1] == "YES" for r in out["rely"]), out["rely"]
assert all(passed for _, passed in out["validation"]), out["validation"]
days, first, last = out["span"][0]
# DuckDB DATE + INTERVAL yields TIMESTAMP (Snowflake keeps DATE); compare the date part.
assert (days, str(first)[:10], str(last)[:10]) == (1095, "2025-01-01", "2027-12-31"), out["span"]
assert all(v == 0 for v in out["keys"][0]), out["keys"]
# The dirty_key guard sums the temp table's columns; a nonzero sum would RAISE.
failing_total = con.execute("SELECT dup_txns + null_txns + dup_customers + null_customers + dup_merchants "
                            "+ null_merchants + dup_refunds + customer_orphans + merchant_orphans + refund_orphans "
                            "FROM key_tests_tmp").fetchone()[0]
assert failing_total == 0, failing_total
assert out["counts"][0][0] == out["counts"][0][1] == fact_rows, out["counts"]
print(f"section 2: calendar 1095 days, key tests all zero, star rows = fact rows = {fact_rows}, "
      f"{len(out['star'])} month/category rows; validation set TRUE x4 against emulated RELY = 'YES' metadata")

# --- section 3 ---------------------------------------------------------------
before_cur = con.execute("SELECT COUNT(*) FROM gold_db_customers.dim_customers WHERE is_current").fetchone()[0]
# duplicate_extract guard: clean extract passes; a duplicated key would RAISE.
dup = con.execute("SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM raw_db_crm.stg_customer_extract").fetchone()[0]
assert dup == 0, dup
con.execute("INSERT INTO raw_db_crm.stg_customer_extract SELECT * FROM raw_db_crm.stg_customer_extract WHERE customer_id='CUST-CH14-0001'")
dup = con.execute("SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM raw_db_crm.stg_customer_extract").fetchone()[0]
assert dup == 1, "guard condition failed to see a duplicated extract key"
con.execute("DELETE FROM raw_db_crm.stg_customer_extract WHERE customer_id='CUST-CH14-0001'")
con.execute("INSERT INTO raw_db_crm.stg_customer_extract VALUES ('CUST-CH14-0001','Priya Raman','priya.raman@example.com',"
            "'77 Bayshore Blvd','Tampa','FL','33606',TIMESTAMP '2026-03-01 06:00:00')")
print("section 3 guard: duplicate-extract condition sees 0 on the fixture and 1 with a planted duplicate")
stmts = statements((CH14 / "chapter14_2_scd_patterns.sql").read_text())
# The Type 2 pair lives inside two Scripting blocks (the worksheet form is a
# comment block). Emulate the rollback demo as a DuckDB transaction, then run
# the executable pair's two statements in order, in place of the skipped blocks.
demo_close = block_statements("chapter14_2_scd_patterns.sql", "Rolled back after closing")
assert len(demo_close) == 1 and demo_close[0].upper().startswith("MERGE"), demo_close
con.execute("BEGIN TRANSACTION")
assert run(demo_close[0], "rollback-demo")[0][0] == 2, "rollback demo close did not affect the two movers"
con.execute("ROLLBACK")
movers_current = con.execute("SELECT COUNT(*) FROM gold_db_customers.dim_customers "
                             "WHERE customer_id IN ('CUST-CH12-0007','CUST-CH12-0042') AND is_current").fetchone()[0]
assert movers_current == 2, movers_current
print("section 3 rollback demo: close affected 2, rolled back, movers still current = 2")
pair = block_statements("chapter14_2_scd_patterns.sql", "inserted := SQLROWCOUNT")
assert len(pair) == 2 and pair[0].upper().startswith("MERGE") and pair[1].upper().startswith("INSERT"), pair
results = {}
for i, st in enumerate(stmts):
    if "inserted := SQLROWCOUNT" in st:
        results["close"] = run(pair[0], "pair-close")
        results["insert"] = run(pair[1], "pair-insert")
        continue
    res = run(st, f"scd#{i}")
    if st.startswith("MERGE INTO gold_db.merchants.dim_merchants tgt\nUSING raw_db.partners.stg_merchant_updates"):
        results["type1"] = res
    elif "stg_merchant_reclass src" in st:
        results["type3"] = res
    elif "AS pit_total" in st:
        results["totals"] = res
    elif "state_at_payment" in st:
        results["movers"] = res
    elif "'type1_new_merchant_present'" in st:
        results["validation"] = res
    elif "NVL(d.state, 'unknown') AS state," in st:
        results["pit"] = res

# DuckDB MERGE returns the number of affected rows as a single count.
assert results["type1"][0][0] == 4, ("type1 affected", results["type1"])
new_m = con.execute("SELECT merchant_name FROM gold_db_merchants.dim_merchants WHERE merchant_id='MERCH-CH14-NEW01'").fetchone()
assert new_m == ("Harbour Kitchen Supply",), new_m
assert results["close"][0][0] == 2, ("close", results["close"])
assert results["insert"][0][0] == 3, ("insert", results["insert"])
assert results["type3"][0][0] == 2, ("type3", results["type3"])
pit_total, current_total = results["totals"][0]
assert pit_total == current_total, (pit_total, current_total)
states = {r[0]: r[1] for r in results["pit"]}
assert "FL" in states and "unknown" in states, states
movers = {(r[0], r[1]): r[2] for r in results["movers"]}
assert all(k[0] in ("CUST-CH12-0007", "CUST-CH12-0042") for k in movers) and any(k[1] == "FL" for k in movers), movers
assert all(passed for _, passed in results["validation"]), results["validation"]
after_cur = con.execute("SELECT COUNT(*) FROM gold_db_customers.dim_customers WHERE is_current").fetchone()[0]
assert after_cur == before_cur + 1, (before_cur, after_cur)
# Idempotence: re-run Type 1 and Type 3 MERGEs, expect zero affected rows.
for st in stmts:
    if st.startswith("MERGE INTO gold_db.merchants.dim_merchants tgt\nUSING raw_db.partners.stg_merchant_updates") \
            or "stg_merchant_reclass src" in st:
        assert run(st, "rerun")[0][0] == 0, "MERGE not idempotent"
# Rerun the executable pair: a replayed extract changes nothing.
for st in pair:
    assert run(st, "scripting-pair-rerun")[0][0] == 0, "Type 2 pair is not a no-op on rerun"
# The ADD COLUMN IF NOT EXISTS statements rerun cleanly.
for st in stmts:
    if "ADD COLUMN IF NOT EXISTS" in st:
        run(st, "rerun-alter")
print(f"section 3: Type1 4 affected (1 new + 3 corrections), SCD2 close 2 / insert 3, Type3 2, "
      f"pit_total == current_total == {pit_total}, states={sorted(states)}, movers={movers}; re-runs affect 0")

# --- section 4 ---------------------------------------------------------------
con.execute("CREATE SCHEMA IF NOT EXISTS vault_db_rawvault; CREATE SCHEMA IF NOT EXISTS vault_db_marts")
out = run_file("chapter14_3_data_vault.sql", [("validation", "'hub_customer_matches_distinct_customers'")])
assert all(passed for _, passed in out["validation"]), out["validation"]
hub = con.execute("SELECT COUNT(*) FROM vault_db_rawvault.hub_customer").fetchone()[0]
sat = con.execute("SELECT COUNT(*) FROM vault_db_rawvault.sat_customer_crm").fetchone()[0]
link = con.execute("SELECT COUNT(*) FROM vault_db_rawvault.link_payment").fetchone()[0]
pit = con.execute("SELECT COUNT(*) FROM vault_db_marts.pit_customer").fetchone()[0]
# Re-run loaders: nothing new.
before = (hub, sat, link)
run_file("chapter14_3_data_vault.sql")
after = tuple(con.execute(f"SELECT COUNT(*) FROM vault_db_rawvault.{t}").fetchone()[0]
              for t in ("hub_customer", "sat_customer_crm", "link_payment"))
assert before == after, (before, after)
# Counterexample: a case/whitespace variant of an existing business key must
# reach the hub MERGE as one source row (grouped by hash key), not two.
vault_sql = (CH14 / "chapter14_3_data_vault.sql").read_text()
src = re.search(r"MERGE INTO vault_db\.rawvault\.hub_customer tgt\s+USING \((.*?)\) src", vault_sql, re.S).group(1)
con.execute("INSERT INTO raw_db_crm.customer_history (customer_id, customer_name, effective_from) "
            "VALUES (' cust-ch12-0007', 'variant spelling', TIMESTAMP '2025-01-01')")
dupes = con.execute(f"SELECT COUNT(*) - COUNT(DISTINCT customer_hk) FROM ({shim(src)}) s").fetchone()[0]
assert dupes == 0, "hub loader source is not unique per hash key with a variant spelling present"
hub_before = con.execute("SELECT COUNT(*) FROM vault_db_rawvault.hub_customer").fetchone()[0]
for st in statements(vault_sql):
    if st.startswith("MERGE INTO vault_db.rawvault.hub_customer"):
        run(st, "hub-variant")
assert con.execute("SELECT COUNT(*) FROM vault_db_rawvault.hub_customer").fetchone()[0] == hub_before, "variant spelling created a second hub row"
# The validation set must agree with the loader's key definition while the
# variant is still present (a raw COUNT(DISTINCT customer_id) would not).
for st in statements(vault_sql):
    if "'hub_customer_matches_distinct_customers'" in st:
        with_variant = run(st, "validation-with-variant")
assert all(passed for _, passed in with_variant), with_variant
con.execute("DELETE FROM raw_db_crm.customer_history WHERE customer_name = 'variant spelling'")
assert con.execute("SELECT COUNT(*) FROM raw_db_crm.customer_history").fetchone()[0] == \
    con.execute("SELECT COUNT(*) FROM gold_db_customers.dim_customers").fetchone()[0], "CRM extract is not every customer version"
assert con.execute("SELECT COUNT(*) FROM raw_db_partners.merchant_directory").fetchone()[0] == \
    con.execute("SELECT COUNT(*) FROM gold_db_merchants.dim_merchants").fetchone()[0], "partner directory is not every merchant"
print(f"section 4: hub {hub}, sat {sat} (movers carry 2 versions), link {link} = facts, pit rows {pit}; loaders idempotent; "
      f"loaders read the two raw_db extracts; variant-spelling key folds into the existing hub row and the validation set stays TRUE with it present")

# --- section 6 ---------------------------------------------------------------
out = run_file("chapter14_4_coco.sql", [
    ("inv", "SELECT check_name, failures\n  FROM gold_db.customers.dim_customers_invariants"),
])
inv = dict(out["inv"])
assert inv == {"current_count_not_one": 0, "current_end_not_sentinel": 0,
               "overlapping_windows": 0, "internal_gap": 0, "invalid_window": 0}, inv
print("section 6: the five invariant checks report zero failures on the section 3 dimension")

# Counterexamples for the view, one broken shape at a time.
INV = "SELECT check_name, failures FROM gold_db_customers.dim_customers_invariants ORDER BY 1"
def with_row(values, expect):
    con.execute("INSERT INTO gold_db_customers.dim_customers (customer_id, customer_name, effective_from, effective_to, is_current, record_hash) "
                f"VALUES {values}")
    got = {k: v for k, v in con.execute(INV).fetchall() if v}
    con.execute("DELETE FROM gold_db_customers.dim_customers WHERE record_hash LIKE 'SIM-CE-%'")
    assert got == expect, (values, got, expect)
    assert not {k: v for k, v in con.execute(INV).fetchall() if v}
with_row("('SIM-ZERO', 'no current version', TIMESTAMP '2025-01-01', TIMESTAMP '2025-06-01', FALSE, 'SIM-CE-1')",
         {"current_count_not_one": 1})
with_row("('SIM-NULLEND', 'current with NULL end', TIMESTAMP '2025-01-01', NULL, TRUE, 'SIM-CE-2')",
         {"current_end_not_sentinel": 1, "invalid_window": 1})
with_row("('SIM-REVERSED', 'reversed window', TIMESTAMP '2025-06-01', TIMESTAMP '9999-12-31', TRUE, 'SIM-CE-3'), "
         "('SIM-REVERSED', 'reversed window', TIMESTAMP '2025-06-01', TIMESTAMP '2025-01-01', FALSE, 'SIM-CE-3')",
         {"invalid_window": 1})
# The reviewer's case: a closed January window, then a current window from
# March. Every other check is clean; only internal_gap sees the February hole.
with_row("('SIM-GAP', 'internal gap', TIMESTAMP '2025-01-01', TIMESTAMP '2025-02-01', FALSE, 'SIM-CE-4'), "
         "('SIM-GAP', 'internal gap', TIMESTAMP '2025-03-01', TIMESTAMP '9999-12-31', TRUE, 'SIM-CE-4')",
         {"internal_gap": 1})
print("section 6 counterexamples: zero-current key, NULL end date, reversed window, internal gap each trip the right check")

# --- teardown ----------------------------------------------------------------
run_file("chapter14_teardown.sql", inline=("dim_merchants_before_ch14", "CALENDAR", "PARTNERS"))
con.execute("DROP SCHEMA IF EXISTS vault_db_rawvault CASCADE; DROP SCHEMA IF EXISTS vault_db_marts CASCADE")
after_m = con.execute("SELECT * FROM gold_db_merchants.dim_merchants ORDER BY 1").fetchall()
after_c = con.execute("SELECT * FROM gold_db_customers.dim_customers ORDER BY customer_key").fetchall()
assert after_m == baseline["dim_merchants"], "dim_merchants not restored"
assert after_c == baseline["dim_customers"], "dim_customers not restored on every column"
assert con.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN ('raw_db_partners','gold_db_calendar')").fetchone()[0] == 0
assert con.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'raw_db_crm' AND table_name IN ('customer_history','stg_customer_extract')").fetchone()[0] == 0
assert con.execute("SELECT COUNT(*) FROM information_schema.columns WHERE table_name='dim_merchants' AND column_name='previous_category'").fetchone()[0] == 0
print("teardown: dim_merchants and dim_customers equal to baseline on every column; fixtures, extracts, calendar, columns gone")

# --- the reviewer's account: no electronics merchant at all -----------------
# Maja Ferle's Chapter 14 run had a dim_merchants without any electronics row.
# The setup must then add its own pair, the Type 3 MERGE must still report 2,
# and the teardown must leave the dimension as it found it.
con.execute("UPDATE gold_db_merchants.dim_merchants SET merchant_category = 'groceries' WHERE upper(merchant_category) = 'ELECTRONICS'")
no_elec_baseline = con.execute("SELECT * FROM gold_db_merchants.dim_merchants ORDER BY 1").fetchall()
con.execute("CREATE SCHEMA IF NOT EXISTS raw_db_partners")
out = run_file("chapter14_0_setup.sql", [("fixtures", "'stg_merchant_updates'  AS fixture")])
fixtures = dict(out["fixtures"])
assert fixtures == {"stg_merchant_updates": 4, "stg_customer_extract": 3, "stg_merchant_reclass": 2,
                    "electronics merchants in dim_merchants": 2}, fixtures
pair = con.execute("SELECT merchant_id FROM gold_db_merchants.dim_merchants WHERE merchant_id LIKE 'MERCH-CH14-ELEC%' ORDER BY 1").fetchall()
assert pair == [("MERCH-CH14-ELEC01",), ("MERCH-CH14-ELEC02",)], pair
reclass = con.execute("SELECT merchant_id FROM raw_db_partners.stg_merchant_reclass ORDER BY 1").fetchall()
assert reclass == pair, reclass
for st in statements((CH14 / "chapter14_2_scd_patterns.sql").read_text()):
    if "ADD COLUMN IF NOT EXISTS" in st:
        run(st, "no-elec-alter")
    elif "stg_merchant_reclass src" in st:
        assert run(st, "no-elec-type3")[0][0] == 2, "Type 3 MERGE did not update the chapter-owned pair"
        break
run_file("chapter14_teardown.sql", inline=("dim_merchants_before_ch14", "CALENDAR", "PARTNERS"))
assert con.execute("SELECT * FROM gold_db_merchants.dim_merchants ORDER BY 1").fetchall() == no_elec_baseline, \
    "dim_merchants not restored after the chapter-owned electronics pair was used"
print("reviewer's case: with no electronics merchant the setup adds MERCH-CH14-ELEC01/02, the reclass fixture targets them, "
      "Type 3 updates 2, and the teardown removes them")

print(f"\n{ran} statements executed, {len(skipped)} skipped (not representable in DuckDB):")
for s in skipped:
    print("  -", s)
print("\nALL LOGIC ASSERTIONS PASSED")
