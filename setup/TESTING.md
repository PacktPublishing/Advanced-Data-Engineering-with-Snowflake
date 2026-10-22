# End-to-end book validation checklist

Use this after [SETUP.md](SETUP.md) to confirm **Snowflake**, **AWS** (including optional **MSK**), **Kafka Connect**, and **Chapter 4** scripts behave as intended. Run steps in order unless your environment already satisfies a phase (e.g. Chapters 2–3 already applied).

---

## Phase A — Snowflake bootstrap

- [ ] Open [snowflake_setup.sql](snowflake_setup.sql) in Snowsight; replace `<REPLACE: your-ip>` in the network rule with your public IP.
- [ ] Execute the full script as `ACCOUNTADMIN` (or equivalent).
- [ ] **Verify:** `SHOW DATABASES LIKE 'UTIL';` — `UTIL` exists.
- [ ] **Verify:** `SHOW WAREHOUSES LIKE 'BOOK_WH';` — warehouse exists and you have `USAGE`.
- [ ] **Verify:** Network policy is attached as documented in the script comments.

---

## Phase B — Terraform backend and AWS (Chapters 2–3 storage)

Skip if you already deployed and trust is configured.

- [ ] [terraform/backend](terraform/backend): `terraform init && terraform apply` (state bucket).
- [ ] [terraform/aws](terraform/aws): copy `terraform.tfvars.example` → `terraform.tfvars`; set `aws_account_id`, `bucket_suffix`, `aws_region`.
- [ ] `terraform apply` (Phase 1 — before Snowflake IAM ARNs on the volume).
- [ ] Run Chapter 2 external volume / integration DDL with `terraform output` values ([chapter2_scripts.sql](../chapters/chapter2/chapter2_scripts.sql) Section 3.1 per book).
- [ ] `DESCRIBE EXTERNAL VOLUME medcore_aws_volume;` — copy `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` into `terraform.tfvars`.
- [ ] `terraform apply` (Phase 2 — trust policies).
- [ ] **Verify:** `SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('medcore_aws_volume');`

---

## Phase B2 — Amazon MSK (Chapter 4 managed Kafka)

- [ ] In [terraform/aws/terraform.tfvars](terraform/aws/terraform.tfvars): set `enable_msk = true`.
- [ ] `cd terraform/aws && terraform apply`
- [ ] **Capture:** `terraform output -raw msk_bootstrap_brokers_sasl_iam` (use for producers and Connect `bootstrap.servers`).

**Networking:** MSK Serverless in this repo lives in a **private VPC**. Producers, Kafka Connect, and `curl` to Connect must run from a host that can reach those brokers. **Simplest (Mac):** enable **`enable_bastion`** in Terraform, paste your **`~/.ssh/*.pub`** into **`bastion_ssh_public_key`**, `terraform apply`, then **`ssh ec2-user@<bastion_public_ip>`** and run **`nc`**, **`dig`**, and **`produce_fraud_events_msk.py`** on the bastion (MSK DNS resolves there). Optional **`enable_vpn`** is WireGuard on ECS for laptop VPN + VPC DNS (more moving parts).

---

## Phase C — Kafka Connect + Snowflake sink (MSK IAM)

**Pre-requisite:** Run [chapter4_kafka_setup.sql](../chapters/chapter4/chapter4_kafka_setup.sql) **Section 2.3** through RSA user setup (`RAW_DB.STREAMING.fraud_events`, `streaming_ingest_role`, `ALTER USER ... RSA_PUBLIC_KEY`).

### Path 1 — MSK Connect (recommended)

MSK Connect is AWS's managed Kafka Connect service. The repo deploys it via Terraform — no self-managed workers needed.

1. **Download the connector plugin:**
   ```bash
   curl -L -o snowflake-kafka-connector-2.4.1.jar \
     "https://repo1.maven.org/maven2/com/snowflake/snowflake-kafka-connector/2.4.1/snowflake-kafka-connector-2.4.1.jar"
   zip snowflake-kafka-connector-2.4.1.zip snowflake-kafka-connector-2.4.1.jar
   ```

2. **Extract your Snowflake RSA private key body** (no `-----BEGIN/END-----` lines):
   ```bash
   grep -v '^\-\-\-\-\-' snowflake_streaming_key.p8 | tr -d '\n'
   ```

3. **Set variables in `terraform.tfvars`:**
   ```hcl
   enable_msk_connect            = true
   snowflake_account_url         = "xy12345.snowflakecomputing.com"
   snowflake_streaming_user      = "STREAMING_INGEST_USER"
   snowflake_private_key_pem     = "MIIEv..."   # output from step 2
   msk_connect_plugin_local_path = "snowflake-kafka-connector-2.4.1.zip"
   ```

4. **Deploy:**
   ```bash
   cd setup/terraform/aws && terraform apply
   ```
   The connector takes ~10 minutes to reach `RUNNING`. Monitor progress:
   ```bash
   aws kafkaconnect list-connectors --region $(terraform output -raw aws_region 2>/dev/null || echo us-west-2)
   ```

- [ ] Connector reaches `RUNNING` state.
- [ ] **Verify:** `terraform output msk_connect_connector_arn` returns an ARN.
- [ ] **Verify:** CloudWatch log group `/msk-connect/medcore-snowflake-connector` shows worker startup logs.

### Path 2 — Self-managed Kafka Connect (alternative)

Use this if you prefer to run Kafka Connect yourself (e.g. on the bastion host or a dedicated EC2).

- [ ] Deploy a Connect worker **in-VPC** with the Snowflake Kafka Connector plugin and **aws-msk-iam-auth** on the classpath ([AWS: Configure clients for IAM access control](https://docs.aws.amazon.com/msk/latest/developerguide/configure-clients-for-iam-access-control.html)).
- [ ] Copy [msk-snowflake-sink-connector.example.json](../chapters/chapter4/kafka/msk-snowflake-sink-connector.example.json); replace all `<REPLACE: ...>` and `${file:...}` paths; confirm `snowflake.role.name` matches your Snowflake role (script uses `streaming_ingest_role` / `STREAMING_INGEST_ROLE`).
- [ ] `curl -X POST http://<connect-host>:8083/connectors -H "Content-Type: application/json" -d @msk-snowflake-sink-connector.example.json`
- [ ] **Verify:** `curl -s http://<connect-host>:8083/connectors/techflow-fraud-streaming-msk/status`

---

## Phase D — Producer to MSK (book dataset)

- [ ] From a host with **MSK network + IAM** access: `cd chapters/chapter4/kafka`
- [ ] `pip install -r requirements-msk.txt`
- [ ] `python3 produce_fraud_events_msk.py --bootstrap "<paste msk_bootstrap_brokers_sasl_iam>" --region <aws-region> --count 200 --bad 5`

**Verify in Snowflake:**

```sql
SELECT COUNT(*), MIN(_loaded_at), MAX(_loaded_at)
FROM RAW_DB.STREAMING.fraud_events
WHERE _loaded_at > DATEADD(minute, -30, CURRENT_TIMESTAMP());
```

---

## Phase D-alt — Local Docker Kafka (no MSK)

- [ ] `cd chapters/chapter4/kafka && docker compose up -d`
- [ ] Use commented `curl` in [chapter4_kafka_setup.sql](../chapters/chapter4/chapter4_kafka_setup.sql) Section 2.3 (`localhost:8083`) — **PLAINTEXT** broker; connector JSON **without** `consumer.override.*` MSK properties.
- [ ] `python3 produce_fraud_events.py` (uses `localhost:9092`)

---

## Phase E — Chapter 4 remainder (SQL)

- [ ] `CREATE DATABASE IF NOT EXISTS RAW_DB;` / `SILVER_DB` if needed.
- [ ] Chapter 4 OpenFlow (optional, paid account): [chapter4_openflow_setup.sql](../chapters/chapter4/chapter4_openflow_setup.sql) Blocks 1–5 (admin role, egress, gen 2 deployment and runtime, canvas), then [chapter4_openflow_teardown.sql](../chapters/chapter4/chapter4_openflow_teardown.sql). Replace `<REPLACE: …>` first.
- [ ] Chapter 4 CDC: [chapter4_cdc_setup.sql](../chapters/chapter4/chapter4_cdc_setup.sql).
- [ ] **§5.x** streams, MERGE, dynamic tables.
- [ ] [chapter4_test_data.sql](../chapters/chapter4/chapter4_test_data.sql) after DDL.

**OpenFlow:** SQL creates the gen 2 deployment and runtime; flows are still built on the Snowsight canvas.

---

## Phase F — Optional Kinesis (AWS)

- [ ] `enable_kinesis = true` in `terraform.tfvars`; `terraform apply`
- [ ] `terraform output -raw kinesis_connector_access_key_id` / `secret_access_key` (sensitive)
- [ ] Follow Block 7 of [chapter4_openflow_setup.sql](../chapters/chapter4/chapter4_openflow_setup.sql) (needs the Block 3–4 deployment and runtime)

---

## Phase G — Optional Azure Event Hubs

- [ ] [terraform/azure](terraform/azure): `terraform init && terraform apply` per [SETUP.md](SETUP.md)
- [ ] Section **4.5** in [chapter4_kafka_setup.sql](../chapters/chapter4/chapter4_kafka_setup.sql)

---

## Quick reference

| Artifact | Purpose |
|----------|---------|
| [chapters/chapter4/kafka/produce_fraud_events_msk.py](../chapters/chapter4/kafka/produce_fraud_events_msk.py) | MSK IAM producer (same JSON as book) |
| [chapters/chapter4/kafka/msk-snowflake-sink-connector.example.json](../chapters/chapter4/kafka/msk-snowflake-sink-connector.example.json) | Snowflake sink + `consumer.override.*` for MSK IAM |
| [setup/terraform/aws/msk-connect.tf](terraform/aws/msk-connect.tf) | MSK Connect Terraform (custom plugin, worker config, connector, IAM) |
| [chapters/chapter4/README.md](../chapters/chapter4/README.md) | Chapter 4 runbook, trial vs paid |
