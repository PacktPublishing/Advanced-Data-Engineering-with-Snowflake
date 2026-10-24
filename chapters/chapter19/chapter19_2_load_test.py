"""Chapter 19, section 2.3: concurrent dashboard-shape load against one warehouse.

Needs: chapter19_0_setup.sql, chapter19_1_bi.sql, and the chapter19_2_interactive.sql
blocks through the freshness block, with INTERACTIVE_WH running. A connection profile in
~/.snowflake/connections.toml for the test user, who holds BI_READER (Chapter 7 pattern).
Use key-pair authentication: each worker opens one session, and a browser or MFA prompt
per session would stall the run. Python 3.11 or later.
    pip install -r requirements.txt
Run three times, inside the same billed hour as the interactive warehouse resume, with the
load results block in chapter19_2_interactive.sql after each run:
    python chapter19_2_load_test.py --connection ch19_test --label standard \
        --warehouse BI_WH --table ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_BENCH
    python chapter19_2_load_test.py --connection ch19_test --label interactive \
        --warehouse INTERACTIVE_WH --table ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_INTERACTIVE
    python chapter19_2_load_test.py --connection ch19_test --label standard_on_interactive \
        --warehouse INTERACTIVE_WH --table ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_BENCH
Validation: run live on the author's sandbox account on 2026-10-24 (three runs, connector 5.1.0,
Python 3.12). The "over 5 s" count is measured on the client and includes network and client
stalls; check a slow sample's elapsed time in Snowflake before calling it fallback.
No credentials in this file. Every query carries QUERY_TAG analytics:load:<label>:<phase>.
"""

import argparse
import csv
import math
import os
import random
import re
import threading
import time
import warnings
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

import snowflake.connector

# Connector 5.1 prints this FutureWarning on every connection, eight times per run.
warnings.filterwarnings("ignore", category=FutureWarning,
                        message=".*enable_server_session_keep_alive_auto_detection.*")

QUERY = """
SELECT event_date, COUNT(*) AS attempts,
       COUNT_IF(approved) AS approved_attempts,
       SUM(IFF(approved, amount_usd, 0)) AS approved_amount_usd
FROM {table}
WHERE merchant_id = %(merchant)s
  AND event_date >= %(start)s::DATE
  AND event_date < DATEADD(day, 30, %(start)s::DATE)
GROUP BY event_date
ORDER BY event_date
"""
TABLES = ("ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_INTERACTIVE",
          "ANALYTICS_DB.SERVING.PAYMENT_ATTEMPTS_BENCH")
MERCHANTS = [f"M{rank:04d}" for rank in range(1, 2001)]
WEIGHTS = [1 / rank for rank in range(1, 2001)]  # same skew as ZIPF(1, 2000)
FIRST_DAY = date(2026, 3, 1)


def pick_parameters(rng):
    merchant = rng.choices(MERCHANTS, weights=WEIGHTS)[0]
    start = FIRST_DAY + timedelta(days=rng.randrange(0, 150))
    return {"merchant": merchant, "start": start.isoformat()}


def run_worker(args, phases, samples, lock, seed):
    rng = random.Random(seed)
    with snowflake.connector.connect(
            connection_name=args.connection,
            role="BI_READER", warehouse=args.warehouse,
            session_parameters={"USE_CACHED_RESULT": False}) as conn:
        cur = conn.cursor()
        for phase, deadline in phases:  # one session for warm-up and measurement
            cur.execute("ALTER SESSION SET QUERY_TAG = "
                        f"'analytics:load:{args.label}:{phase}'")
            while time.monotonic() < deadline:
                params = pick_parameters(rng)
                started = time.perf_counter()
                error, query_id = "", ""
                try:
                    cur.execute(QUERY.format(table=args.table), params)
                    cur.fetchall()
                    query_id = cur.sfqid or ""
                except snowflake.connector.Error as exc:
                    error = f"{exc.errno}: {exc.msg}"
                    query_id = getattr(exc, "sfqid", None) or ""
                elapsed_ms = (time.perf_counter() - started) * 1000
                with lock:
                    samples.append({"phase": phase, "merchant": params["merchant"],
                                    "start": params["start"],
                                    "elapsed_ms": round(elapsed_ms, 1),
                                    "query_id": query_id, "error": error})


def run_load(args, samples):
    warmup_end = time.monotonic() + args.warmup
    phases = [("warmup", warmup_end), ("measure", warmup_end + args.duration)]
    lock = threading.Lock()
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = [pool.submit(run_worker, args, phases, samples, lock, worker)
                   for worker in range(args.concurrency)]
    for future in futures:
        future.result()  # re-raise connection failures instead of hiding them


def label(value):
    if not re.fullmatch(r"[A-Za-z0-9_]+", value):
        raise argparse.ArgumentTypeError("use letters, digits, and underscores only")
    return value


def percentile(values, fraction):
    """Nearest-rank percentile: the smallest value covering the fraction."""
    ordered = sorted(values)
    rank = max(1, math.ceil(fraction * len(ordered)))
    return ordered[rank - 1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", required=True, type=label)
    parser.add_argument("--warehouse", required=True,
                        choices=("INTERACTIVE_WH", "BI_WH"))
    parser.add_argument("--table", required=True, choices=TABLES)
    parser.add_argument("--connection",
                        default=os.environ.get("SNOWFLAKE_CONNECTION", "default"))
    parser.add_argument("--concurrency", type=int, default=8)
    parser.add_argument("--warmup", type=int, default=120)
    parser.add_argument("--duration", type=int, default=300)
    args = parser.parse_args()

    samples = []
    run_load(args, samples)
    if not samples:
        raise SystemExit("No queries completed; check the connection profile and grants.")
    measured = [s for s in samples if s["phase"] == "measure"]
    good = [s["elapsed_ms"] for s in measured if not s["error"]]
    with open(f"load_{args.label}.csv", "w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=list(samples[0]))
        writer.writeheader()
        writer.writerows(samples)
    print(f"{args.label}: {len(good)} completed, "
          f"{len(measured) - len(good)} failed, "
          f"{len(good) / args.duration:.1f} requests/s")
    if good:
        print(f"p50 {percentile(good, 0.50):.0f} ms, "
              f"p95 {percentile(good, 0.95):.0f} ms, "
              f"over 5 s: {sum(1 for v in good if v > 5000)}")


if __name__ == "__main__":
    main()
