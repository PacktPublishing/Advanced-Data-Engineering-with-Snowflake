#!/usr/bin/env python3
"""
Produce book-aligned fraud events to Amazon MSK (SASL/IAM).

Prerequisites:
  - Network path from this host to MSK bootstrap brokers (same VPC, VPN, SSM tunnel, etc.)
  - IAM principal allowed to connect/produce (e.g. kafka-cluster:Connect, kafka:WriteData on topic)
  - For MSK Serverless: topics are created via the Kafka CreateTopics API (this script does that by
    default). The AWS CLI "aws kafka create-topic" is NOT supported on serverless clusters.

Install:
  pip install -r requirements-msk.txt

Usage:
  export AWS_REGION=us-east-1   # or pass --region
  python3 produce_fraud_events_msk.py \\
    --bootstrap "$(terraform -chdir=../../../setup/terraform/aws output -raw msk_bootstrap_brokers_sasl_iam)" \\
    --region ca-central-1 \\
    --count 500 --bad 10
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from datetime import datetime, timedelta

from confluent_kafka import KafkaError, KafkaException, Producer
from confluent_kafka.admin import AdminClient, NewTopic

from fraud_events_common import (
    TOPIC,
    bad_event_missing_fields,
    bad_event_wrong_type,
    random_event,
)


def _try_import_signer():
    try:
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

        return MSKAuthTokenProvider
    except ImportError as e:
        print(
            "Missing dependency: pip install -r requirements-msk.txt\n"
            f"Import error: {e}",
            file=sys.stderr,
        )
        sys.exit(1)


def delivery_report(err, msg):
    if err:
        print(f"FAIL: {err}")


def _msk_client_conf(bootstrap: str, region: str, client_id: str) -> dict:
    MSKAuthTokenProvider = _try_import_signer()

    def oauth_cb(_oauth_config: str):
        auth_token, expiry_ms = MSKAuthTokenProvider.generate_auth_token(region)
        return auth_token, expiry_ms / 1000.0

    return {
        "bootstrap.servers": bootstrap,
        "security.protocol": "SASL_SSL",
        "sasl.mechanism": "OAUTHBEARER",
        "oauth_cb": oauth_cb,
        "client.id": client_id,
    }


def ensure_topic_msk(
    bootstrap: str,
    region: str,
    topic: str,
    partitions: int,
    replication_factor: int,
) -> None:
    """MSK Serverless: create topic via Kafka Admin API (not aws kafka create-topic)."""
    admin = AdminClient(_msk_client_conf(bootstrap, region, "book-ch4-fraud-admin-msk"))
    fs = admin.create_topics(
        [NewTopic(topic, num_partitions=partitions, replication_factor=replication_factor)],
        request_timeout=60,
        operation_timeout=60,
    )
    for name, fut in fs.items():
        try:
            fut.result()
            print(f"Created Kafka topic {name!r} ({partitions}p, rf={replication_factor}).")
        except KafkaException as e:
            code = e.args[0].code() if e.args else None
            if code == KafkaError.TOPIC_ALREADY_EXISTS:
                print(f"Topic {name!r} already exists.")
                return
            raise


def build_producer(bootstrap: str, region: str) -> Producer:
    return Producer(_msk_client_conf(bootstrap, region, "book-ch4-fraud-producer-msk"))


def main():
    parser = argparse.ArgumentParser(description="Produce fraud-events to MSK (IAM auth)")
    parser.add_argument(
        "--bootstrap",
        required=True,
        help="MSK bootstrap brokers (SASL/IAM), e.g. from terraform output msk_bootstrap_brokers_sasl_iam",
    )
    parser.add_argument(
        "--region",
        default=None,
        help="AWS region for MSK IAM signing (default: AWS_REGION env or boto3 session)",
    )
    parser.add_argument("--topic", default=TOPIC, help=f"Kafka topic (default: {TOPIC})")
    parser.add_argument(
        "--no-create-topic",
        action="store_true",
        help="Skip CreateTopics (topic must already exist)",
    )
    parser.add_argument(
        "--partitions",
        type=int,
        default=6,
        help="Partitions when creating topic (MSK Serverless)",
    )
    parser.add_argument(
        "--replication-factor",
        type=int,
        default=2,
        help="Replication factor when creating topic (try 2 or 3 if create fails)",
    )
    parser.add_argument("--count", type=int, default=1000, help="Valid events")
    parser.add_argument("--bad", type=int, default=50, help="Malformed events (DLQ testing)")
    args = parser.parse_args()

    region = args.region
    if not region:
        import os

        region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    if not region:
        try:
            import boto3

            region = boto3.session.Session().region_name
        except Exception:
            pass
    if not region:
        print("Pass --region or set AWS_REGION.", file=sys.stderr)
        sys.exit(1)

    if not args.no_create_topic:
        ensure_topic_msk(
            args.bootstrap,
            region,
            args.topic,
            args.partitions,
            args.replication_factor,
        )

    producer = build_producer(args.bootstrap, region)

    base_ts = datetime.utcnow() - timedelta(minutes=5)

    print(f"Producing {args.count} valid + {args.bad} bad events to {args.topic} (MSK IAM)...")
    for i in range(args.count):
        ts = base_ts + timedelta(milliseconds=i * 300)
        evt = random_event(ts)
        producer.produce(
            args.topic,
            key=evt["event_id"],
            value=json.dumps(evt),
            callback=delivery_report,
        )
        if i % 500 == 0:
            producer.flush()

    bad_generators = [bad_event_wrong_type, bad_event_missing_fields]
    for _ in range(args.bad):
        evt = random.choice(bad_generators)()
        producer.produce(
            args.topic,
            key=evt.get("event_id", "bad"),
            value=json.dumps(evt),
            callback=delivery_report,
        )

    producer.flush()
    print("Done.")


if __name__ == "__main__":
    main()
