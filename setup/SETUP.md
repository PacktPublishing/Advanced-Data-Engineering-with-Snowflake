# Setup

## Prerequisites
- Snowflake trial account (AWS, Enterprise edition) → https://signup.snowflake.com
- AWS account (free tier is fine)
- AWS CLI >= 2.32.0
- Terraform >= 1.5
- Snowflake CLI (`snow`) recommended for scripted chapters

## Steps

1. **Create Snowflake trial** — AWS, Enterprise edition. Confirm email, log in as ACCOUNTADMIN.

2. **Run Snowflake setup** — Open `setup/snowflake_setup.sql` in Snowsight. Before running, replace `<REPLACE: your-ip>` in the network rule with your public IP (find it at https://api.ipify.org). Run all statements. Copy the PAT token from the output — it is shown only once.

3. **(Optional) Configure Cursor MCP** — Run from the repo root:
   ```
   ./setup/generate_mcp_config.sh \
     --account-url "https://<ORG>-<ACCOUNT>.snowflakecomputing.com" \
     --database UTIL \
     --schema AI \
     --mcp-server book_sql_exec_server \
     --pat "<your-pat-token>"
   ```
   Restart Cursor.

4. **Authenticate to AWS** — Use `aws login` (no access keys needed):
   ```
   aws login
   ```
   A browser window opens — sign in with your AWS console credentials (root or IAM user). The CLI receives temporary credentials that auto-rotate every 15 minutes. Verify with:
   ```
   aws sts get-caller-identity
   ```
   Terraform and the AWS CLI will pick up these credentials automatically.

   > Requires AWS CLI 2.32.0+. See [Simplified developer access to AWS with `aws login`](https://aws.amazon.com/blogs/security/simplified-developer-access-to-aws-with-aws-login/) for details.

5. **Bootstrap Terraform backend** —
   ```
   cd setup/terraform/backend
   cp terraform.tfvars.example terraform.tfvars   # edit bucket_suffix
   terraform init && terraform apply
   ```

6. **Deploy AWS infra (Phase 1)** —
   ```
   cd setup/terraform/aws
   cp terraform.tfvars.example terraform.tfvars   # edit aws_account_id, bucket_suffix, aws_region
   terraform init && terraform apply
   ```

7. **Create external volume in Snowflake** — Run section 3.1 from `chapters/chapter2/chapter2_scripts.sql` using Terraform outputs:
   ```
   terraform output -json   # get bucket name + role ARN
   ```

8. **Get Snowflake IAM ARNs** — Run `DESCRIBE EXTERNAL VOLUME medcore_aws_volume` in Snowflake. Copy `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID`.

9. **Deploy AWS infra (Phase 2)** — Update `terraform.tfvars` with the Snowflake ARNs from step 8, then:
   ```
   terraform apply
   ```

10. **Verify** — Run `SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('medcore_aws_volume');` in Snowflake. Should succeed.

11. **Run chapter scripts** — Follow the [root README](../README.md) chapter index. Each `chapters/chapterN/README.md` lists scripts, databases, and teardown.

## After setup: run the book in order

Use the [chapter index in the root README](../README.md). Run each script **section by section** in Snowsight or the Snowflake CLI. Replace every `<REPLACE: ...>` placeholder before executing that statement.

### How to run SQL

- **Snowsight** — Open the worksheet, paste a section, run. Easiest for most readers.
- **SnowSQL** — `snowsql -c book -f <script>.sql` works for every chapter; replace every `<REPLACE: …>` first. The Chapter 4 OpenFlow canvas steps are comments and run only in Snowsight. Ensure `[connections.book]` in `~/.snowsql/config` points at the right account.

### Chapter 4 — databases and optional pieces

- **`RAW_DB` / `SILVER_DB`** — Chapter 4 assumes these exist. Chapter 2–3 use **`MEDCORE_DEMO`** only; align with the book or create the two databases before Chapter 4.
- **Kafka / MSK / Kinesis / Event Hubs** — Optional; see steps 12–14 below and [chapters/chapter4/README.md](../chapters/chapter4/README.md).
- **Trial accounts** — You may need to skip **External Access Integration**, **OpenFlow pipeline** sections, and similar (see the header comments in `chapter4_openflow_setup.sql`).

### Chapter 4 — Optional Streaming Infrastructure

12. **(Optional) Deploy MSK Serverless + Kinesis** — For Chapter 4 Kafka and OpenFlow Kinesis exercises. Edit `terraform.tfvars`:
    ```
    enable_msk     = true   # MSK Serverless cluster + VPC
    enable_kinesis = true   # Kinesis Data Stream + IAM user
    ```
    Then:
    ```
    cd setup/terraform/aws
    terraform apply
    ```
    Retrieve Kinesis connector credentials:
    ```
    terraform output -raw kinesis_connector_access_key_id
    terraform output -raw kinesis_connector_secret_access_key
    ```

12b. **(Optional) Deploy MSK Connect** — Managed Kafka Connect for the Snowflake sink (requires `enable_msk = true` from step 12). This replaces the need for self-managed Kafka Connect workers.

    Download and package the Snowflake Kafka Connector:
    ```bash
    curl -L -o snowflake-kafka-connector-2.4.1.jar \
      "https://repo1.maven.org/maven2/com/snowflake/snowflake-kafka-connector/2.4.1/snowflake-kafka-connector-2.4.1.jar"
    zip snowflake-kafka-connector-2.4.1.zip snowflake-kafka-connector-2.4.1.jar
    ```

    Extract the RSA private key body (no header/footer):
    ```bash
    grep -v '^\-\-\-\-\-' snowflake_streaming_key.p8 | tr -d '\n'
    ```

    Add to `terraform.tfvars`:
    ```hcl
    enable_msk_connect            = true
    snowflake_account_url         = "xy12345.snowflakecomputing.com"
    snowflake_streaming_user      = "STREAMING_INGEST_USER"
    snowflake_private_key_pem     = "MIIEv..."
    msk_connect_plugin_local_path = "snowflake-kafka-connector-2.4.1.zip"
    ```

    Then:
    ```bash
    cd setup/terraform/aws
    terraform apply
    ```

    The connector takes ~10 minutes to deploy. Verify:
    ```bash
    terraform output msk_connect_connector_arn
    ```

13. **(Optional) Deploy Azure Event Hubs** — For Chapter 4 Event Hubs exercise. Requires Azure CLI authenticated (`az login`):
    ```
    cd setup/terraform/azure
    cp terraform.tfvars.example terraform.tfvars   # edit azure_subscription_id
    terraform init && terraform apply
    ```
    Retrieve connection string:
    ```
    terraform output -raw eventhub_connection_string
    ```

14. **(Optional) Local Kafka** — For Chapter 4 Kafka exercises without MSK:
    ```
    cd chapters/chapter4/kafka
    docker compose up -d
    ```

## End-to-end validation

See **[TESTING.md](TESTING.md)** for a full checklist: Snowflake bootstrap, Terraform (including `enable_msk` / `enable_kinesis` / `enable_msk_connect`), **MSK Connect** (recommended) or self-managed **Kafka Connect** in the MSK VPC with **IAM** auth, **MSK producer** ([chapters/chapter4/kafka/produce_fraud_events_msk.py](../chapters/chapter4/kafka/produce_fraud_events_msk.py)), and Chapter 4 SQL.

## Teardown
```
cd setup/terraform/aws && terraform destroy
cd setup/terraform/azure && terraform destroy   # if deployed
cd setup/terraform/backend && terraform destroy
```
Stop local Kafka:
```
cd chapters/chapter4/kafka && docker compose down -v
```
Drop Snowflake objects:
```sql
DROP DATABASE IF EXISTS MEDCORE_DEMO;
DROP DATABASE IF EXISTS RAW_DB;
DROP DATABASE IF EXISTS SILVER_DB;
DROP DATABASE IF EXISTS UTIL;
DROP DATABASE IF EXISTS GENOMICS_DB;
DROP NETWORK POLICY IF EXISTS book_network_policy;
```
