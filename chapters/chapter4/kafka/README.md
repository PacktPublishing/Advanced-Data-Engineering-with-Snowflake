# Local Kafka and Kafka Connect (Chapter 4 helper)

This folder is for **local** Kafka + Kafka Connect so you can run **Section 2.3–2.4** (and similar) without **Amazon MSK**.

**Full Chapter 4 context** (what to skip on trial, OpenFlow, Kinesis, Event Hubs): see [../README.md](../README.md).

## Which path am I on?

| Path | Producer script | Snowflake sink config |
|------|-----------------|------------------------|
| **Local Kafka** (this folder) | `produce_fraud_events.py` | Commented `curl` in [chapter4_kafka_setup.sql](../chapter4_kafka_setup.sql) **Section 2.3** — post to `http://localhost:8083/connectors` |
| **Amazon MSK + MSK Connect** (recommended) | `produce_fraud_events_msk.py` + `requirements-msk.txt` (SASL/IAM; run from bastion) | Terraform `enable_msk_connect = true` deploys the Snowflake sink automatically — see [setup/SETUP.md](../../../setup/SETUP.md) step 12b |
| **Amazon MSK + self-managed Connect** | `produce_fraud_events_msk.py` + `requirements-msk.txt` (SASL/IAM; run from VPC or host with broker reachability) | [msk-snowflake-sink-connector.example.json](msk-snowflake-sink-connector.example.json) — worker needs **aws-msk-iam-auth** on classpath; see [setup/TESTING.md](../../../setup/TESTING.md) Phase C Path 2 |
| **AWS Kinesis** (OpenFlow connector) | `produce_kinesis_events.py` (needs `boto3`, AWS credentials) | Block 7 of [chapter4_openflow_setup.sql](../chapter4_openflow_setup.sql) + AWS infra in [setup/SETUP.md](../../../setup/SETUP.md) |
| **Azure Event Hubs** | Any Kafka producer against the Event Hubs endpoint, or reuse patterns from the book | Section **4.5** in [chapter4_kafka_setup.sql](../chapter4_kafka_setup.sql) (SASL_SSL / `$ConnectionString`) |

Shared payload helpers live in **`fraud_events_common.py`** (used by both local and MSK producers).

## Quick start (local Kafka)

```bash
# 1. Start Kafka + Kafka Connect
docker compose up -d

# 2. Wait for Kafka Connect to be ready (~60s for connector install)
curl -s http://localhost:8083/connector-plugins | jq '.[].class' | grep -i snowflake

# 3. Place your Snowflake private key in ./secrets/
#    (from the openssl steps in chapter4_kafka_setup.sql Section 2.3)
cp /path/to/snowflake_streaming_key.p8 ./secrets/

# 4. Deploy the Snowflake sink connector — copy the curl block from
#    chapter4_kafka_setup.sql Section 2.3; set snowflake.url.name, user, role, etc.

# 5. Produce test messages to topic fraud-events
pip install confluent-kafka   # if needed
python3 produce_fraud_events.py
```

## Producer scripts in this directory

- **`produce_fraud_events.py`** — Sends JSON to **`fraud-events`** via **PLAINTEXT** `localhost:9092` (Docker Compose).
- **`produce_fraud_events_msk.py`** — Same JSON shape; **Amazon MSK** with **IAM** (`OAUTHBEARER`). Install `requirements-msk.txt`.
- **`produce_kinesis_events.py`** — Sends JSON to an **AWS Kinesis** stream named `fraud-events`. Use with Block 7 of `chapter4_openflow_setup.sql` (OpenFlow Kinesis bonus lab) (requires AWS credentials and a deployed stream).

## Teardown

```bash
docker compose down -v
```
