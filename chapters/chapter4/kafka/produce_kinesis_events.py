#!/usr/bin/env python3
"""
Produce test fraud-event messages to an AWS Kinesis Data Stream.

Requires: pip install boto3
Usage:    python3 produce_kinesis_events.py [--count 500] [--stream fraud-events] [--region ca-central-1]

Uses default AWS credentials (aws login / environment variables / ~/.aws/credentials).
"""

import argparse
import json
import random
import string
import uuid
from datetime import datetime, timedelta

import boto3

MERCHANTS = [f"merch-{i:03d}" for i in range(1, 51)]
EVENT_TYPES = ["authorization", "capture", "refund", "chargeback", "decline"]


def random_event(ts: datetime) -> dict:
    return {
        "event_id": f"evt-{uuid.uuid4().hex[:12]}",
        "transaction_id": f"txn-{uuid.uuid4().hex[:8]}",
        "amount": round(random.uniform(1.00, 9999.99), 2),
        "merchant_id": random.choice(MERCHANTS),
        "card_hash": f"sha256-{''.join(random.choices(string.hexdigits[:16], k=16))}",
        "event_type": random.choice(EVENT_TYPES),
        "risk_score": round(random.uniform(0, 100), 2),
        "event_timestamp": ts.strftime("%Y-%m-%dT%H:%M:%S"),
        "payload": {
            "ip": f"{random.randint(1,223)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}",
            "device_fingerprint": f"fp-{uuid.uuid4().hex[:8]}",
        },
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=500)
    parser.add_argument("--stream", default="fraud-events")
    parser.add_argument("--region", default="ca-central-1")
    args = parser.parse_args()

    client = boto3.client("kinesis", region_name=args.region)
    base_ts = datetime.utcnow() - timedelta(minutes=5)

    records = []
    for i in range(args.count):
        ts = base_ts + timedelta(milliseconds=i * 600)
        evt = random_event(ts)
        records.append({
            "Data": json.dumps(evt).encode(),
            "PartitionKey": evt["merchant_id"],
        })
        if len(records) == 100:
            resp = client.put_records(StreamName=args.stream, Records=records)
            failed = resp.get("FailedRecordCount", 0)
            print(f"Batch sent: {100 - failed} OK, {failed} failed")
            records = []

    if records:
        resp = client.put_records(StreamName=args.stream, Records=records)
        failed = resp.get("FailedRecordCount", 0)
        print(f"Final batch: {len(records) - failed} OK, {failed} failed")

    print(f"Done. Sent {args.count} events to {args.stream}.")


if __name__ == "__main__":
    main()
