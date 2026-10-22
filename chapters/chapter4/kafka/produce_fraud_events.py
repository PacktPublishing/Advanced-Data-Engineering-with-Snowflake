#!/usr/bin/env python3
"""
Produce test fraud-event messages to the local Kafka topic.

Requires: pip install confluent-kafka
Usage:    python3 produce_fraud_events.py [--count 1000] [--bad 50]
"""

import argparse
import json
import random
from datetime import datetime, timedelta

from confluent_kafka import Producer

from fraud_events_common import (
    TOPIC,
    bad_event_missing_fields,
    bad_event_wrong_type,
    random_event,
)

BOOTSTRAP = "localhost:9092"


def delivery_report(err, msg):
    if err:
        print(f"FAIL: {err}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=1000, help="Number of valid events")
    parser.add_argument("--bad", type=int, default=50, help="Number of malformed events (for DLQ)")
    args = parser.parse_args()

    producer = Producer({"bootstrap.servers": BOOTSTRAP})

    base_ts = datetime.utcnow() - timedelta(minutes=5)

    print(f"Producing {args.count} valid + {args.bad} bad events to {TOPIC}...")
    for i in range(args.count):
        ts = base_ts + timedelta(milliseconds=i * 300)
        evt = random_event(ts)
        producer.produce(TOPIC, key=evt["event_id"], value=json.dumps(evt), callback=delivery_report)
        if i % 500 == 0:
            producer.flush()

    bad_generators = [bad_event_wrong_type, bad_event_missing_fields]
    for _ in range(args.bad):
        evt = random.choice(bad_generators)()
        producer.produce(TOPIC, key=evt.get("event_id", "bad"), value=json.dumps(evt), callback=delivery_report)

    producer.flush()
    print("Done.")


if __name__ == "__main__":
    main()
