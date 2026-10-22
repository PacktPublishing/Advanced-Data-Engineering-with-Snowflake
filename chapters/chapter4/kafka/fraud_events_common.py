"""
Shared fraud-event JSON generators for Chapter 4 Kafka labs.

Used by produce_fraud_events.py (local Docker / PLAINTEXT) and
produce_fraud_events_msk.py (Amazon MSK with IAM).
"""

from __future__ import annotations

import random
import string
import uuid
from datetime import datetime, timedelta

TOPIC = "fraud-events"

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


def bad_event_wrong_type() -> dict:
    """amount is a string instead of number -- may trigger DLQ."""
    evt = random_event(datetime.utcnow())
    evt["amount"] = "not-a-number"
    return evt


def bad_event_missing_fields() -> dict:
    """Missing required fields -- may trigger DLQ."""
    return {
        "event_id": f"evt-{uuid.uuid4().hex[:12]}",
        "event_type": "authorization",
    }
