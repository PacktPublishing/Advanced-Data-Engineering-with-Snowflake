"""Generate sample Avro file for Chapter 8 Section 4.2 external table test.

Produces payment_events.avro with 10 synthetic payment events matching the
schema the ext_payment_events external table expects.

Usage:
    python data/gen_payment_events_avro.py
    aws s3 cp data/payment_events.avro s3://<REPLACE: your-lake-bucket>/payment_events/
"""

import datetime
import uuid
from pathlib import Path

import fastavro

SCHEMA = {
    "type": "record",
    "name": "PaymentEvent",
    "namespace": "com.techflow.payments",
    "fields": [
        {"name": "event_id", "type": "string"},
        {"name": "merchant_id", "type": "string"},
        {"name": "amount", "type": "double"},
        {"name": "currency", "type": "string"},
        {"name": "status", "type": "string"},
        {"name": "event_ts", "type": {"type": "long", "logicalType": "timestamp-millis"}},
    ],
}

MERCHANTS = ["MERCH_ELEC_1", "MERCH_GROC_1", "MERCH_TRVL_1", "MERCH_GROC_2", "MERCH_GAP"]
STATUSES = ["COMPLETED", "PENDING", "FAILED"]

BASE_TS = datetime.datetime(2026, 6, 1, 12, 0, 0, tzinfo=datetime.timezone.utc)


def generate_records(n: int = 10) -> list[dict]:
    records = []
    for i in range(n):
        records.append(
            {
                "event_id": str(uuid.uuid4()),
                "merchant_id": MERCHANTS[i % len(MERCHANTS)],
                "amount": round(50.0 + i * 123.45, 2),
                "currency": "USD",
                "status": STATUSES[i % len(STATUSES)],
                "event_ts": int((BASE_TS + datetime.timedelta(hours=i)).timestamp() * 1000),
            }
        )
    return records


def main():
    out = Path(__file__).parent / "payment_events.avro"
    records = generate_records()
    with out.open("wb") as f:
        fastavro.writer(f, SCHEMA, records)
    print(f"Wrote {len(records)} records to {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
