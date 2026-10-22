# -----------------------------------------------------------------------------
# Chapter 4: MSK Connect — managed Kafka Connect for Snowflake sink
# Gated behind enable_msk_connect (requires enable_msk = true).
#
# Resources:
#   1. S3 object — Snowflake Kafka Connector ZIP uploaded to the lakehouse bucket
#   2. Custom plugin — references the S3 ZIP
#   3. Worker configuration — IAM auth + Snowflake-tuned worker properties
#   4. IAM execution role — kafka-cluster:*, S3 plugin read, CloudWatch logs
#   5. Security group — connector workers in the streaming VPC
#   6. CloudWatch log group — connector worker logs
#   7. Connector — ties everything together
#
# The connector ZIP must exist locally before `terraform apply`.
# Download from: https://mvnrepository.com/artifact/com.snowflake/snowflake-kafka-connector
# or Confluent Hub: confluent-hub install snowflakeinc/snowflake-kafka-connector:2.4.1
#
# Example (download JAR, package as ZIP for MSK Connect):
#   curl -L -o snowflake-kafka-connector-2.4.1.jar \
#     "https://repo1.maven.org/maven2/com/snowflake/snowflake-kafka-connector/2.4.1/snowflake-kafka-connector-2.4.1.jar"
#   zip snowflake-kafka-connector-2.4.1.zip snowflake-kafka-connector-2.4.1.jar
#
# Then set: msk_connect_plugin_local_path = "snowflake-kafka-connector-2.4.1.zip"
# -----------------------------------------------------------------------------

check "msk_connect_requires_msk" {
  assert {
    condition     = !var.enable_msk_connect || var.enable_msk
    error_message = "enable_msk_connect requires enable_msk (same VPC and cluster)."
  }
}

check "msk_connect_requires_snowflake_url" {
  assert {
    condition     = !var.enable_msk_connect || length(trimspace(var.snowflake_account_url)) > 0
    error_message = "Set snowflake_account_url when enable_msk_connect is true."
  }
}

check "msk_connect_requires_snowflake_user" {
  assert {
    condition     = !var.enable_msk_connect || length(trimspace(var.snowflake_streaming_user)) > 0
    error_message = "Set snowflake_streaming_user when enable_msk_connect is true."
  }
}

check "msk_connect_requires_private_key" {
  assert {
    condition     = !var.enable_msk_connect || length(trimspace(var.snowflake_private_key_pem)) > 0
    error_message = "Set snowflake_private_key_pem when enable_msk_connect is true."
  }
}

check "msk_connect_requires_plugin" {
  assert {
    condition     = !var.enable_msk_connect || length(trimspace(var.msk_connect_plugin_local_path)) > 0
    error_message = "Set msk_connect_plugin_local_path to the local Snowflake Kafka Connector ZIP."
  }
}

# ---------------------------------------------------------------------------
# 1. Upload connector plugin ZIP to S3
# ---------------------------------------------------------------------------
resource "aws_s3_object" "snowflake_kafka_connector" {
  count  = var.enable_msk && var.enable_msk_connect ? 1 : 0
  bucket = aws_s3_bucket.medcore_lakehouse.id
  key    = "msk-connect-plugins/snowflake-kafka-connector.zip"
  source = var.msk_connect_plugin_local_path
  etag   = filemd5(var.msk_connect_plugin_local_path)

  tags = { Chapter = "4" }
}

# ---------------------------------------------------------------------------
# 2. MSK Connect custom plugin
# ---------------------------------------------------------------------------
resource "aws_mskconnect_custom_plugin" "snowflake" {
  count        = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name         = "snowflake-kafka-connector"
  content_type = "ZIP"
  description  = "Snowflake Kafka Connector for Snowpipe Streaming"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.medcore_lakehouse.arn
      file_key   = aws_s3_object.snowflake_kafka_connector[0].key
    }
  }

  tags = { Chapter = "4" }
}

# ---------------------------------------------------------------------------
# 3. Worker configuration (IAM auth properties for the Connect worker)
# ---------------------------------------------------------------------------
resource "aws_mskconnect_worker_configuration" "snowflake" {
  count       = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name        = "medcore-snowflake-worker-config"
  description = "Worker config for Snowflake Kafka Connector with MSK IAM auth"

  properties_file_content = <<-EOT
    key.converter=org.apache.kafka.connect.storage.StringConverter
    value.converter=org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable=false
    offset.flush.interval.ms=30000
  EOT
}

# ---------------------------------------------------------------------------
# 4. IAM execution role for MSK Connect
# ---------------------------------------------------------------------------
resource "aws_iam_role" "msk_connect" {
  count = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name  = "medcore-msk-connect-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "kafkaconnect.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Chapter = "4" }
}

# MSK cluster + topic access (same pattern as bastion role in bastion.tf)
resource "aws_iam_role_policy" "msk_connect_kafka" {
  count = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name  = "msk-kafka-access"
  role  = aws_iam_role.msk_connect[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KafkaClusterConnect"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = aws_msk_serverless_cluster.fraud_events[0].arn
      },
      {
        Sid    = "KafkaTopics"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:DeleteTopic"
        ]
        Resource = [
          "${replace(aws_msk_serverless_cluster.fraud_events[0].arn, ":cluster/", ":topic/")}/*",
          "arn:aws:kafka:${var.aws_region}:${var.aws_account_id}:topic/${aws_msk_serverless_cluster.fraud_events[0].cluster_uuid}/*"
        ]
      },
      {
        Sid    = "KafkaConsumerGroups"
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = [
          "${replace(aws_msk_serverless_cluster.fraud_events[0].arn, ":cluster/", ":group/")}/*",
          "arn:aws:kafka:${var.aws_region}:${var.aws_account_id}:group/${aws_msk_serverless_cluster.fraud_events[0].cluster_uuid}/*"
        ]
      }
    ]
  })
}

# S3 read access for custom plugin
resource "aws_iam_role_policy" "msk_connect_s3" {
  count = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name  = "s3-plugin-access"
  role  = aws_iam_role.msk_connect[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetBucketLocation"
      ]
      Resource = [
        aws_s3_bucket.medcore_lakehouse.arn,
        "${aws_s3_bucket.medcore_lakehouse.arn}/msk-connect-plugins/*"
      ]
    }]
  })
}

# CloudWatch Logs write access
resource "aws_iam_role_policy" "msk_connect_logs" {
  count = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name  = "cloudwatch-logs"
  role  = aws_iam_role.msk_connect[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.msk_connect[0].arn}:*"
    }]
  })
}

# ---------------------------------------------------------------------------
# 5. Security group for MSK Connect workers
# ---------------------------------------------------------------------------
resource "aws_security_group" "msk_connect" {
  count       = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name_prefix = "medcore-msk-connect-"
  description = "MSK Connect workers: MSK IAM + HTTPS to Snowflake"
  vpc_id      = aws_vpc.streaming[0].id

  # Outbound to MSK (port 9098 for IAM auth)
  egress {
    description = "Kafka IAM to MSK Serverless"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.streaming[0].cidr_block]
  }

  # Outbound HTTPS (Snowflake API + general)
  egress {
    description = "HTTPS to Snowflake and AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "medcore-msk-connect-sg" }
}

# Also allow MSK Connect workers to reach MSK via the existing MSK security group
resource "aws_security_group_rule" "msk_allow_connect" {
  count                    = var.enable_msk && var.enable_msk_connect ? 1 : 0
  type                     = "ingress"
  from_port                = 9098
  to_port                  = 9098
  protocol                 = "tcp"
  description              = "Allow MSK Connect workers"
  security_group_id        = aws_security_group.msk[0].id
  source_security_group_id = aws_security_group.msk_connect[0].id
}

# ---------------------------------------------------------------------------
# 6. CloudWatch log group for connector worker logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "msk_connect" {
  count             = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name              = "/msk-connect/medcore-snowflake-connector"
  retention_in_days = 7

  tags = { Chapter = "4" }
}

# ---------------------------------------------------------------------------
# 7. MSK Connect connector — Snowflake sink for fraud-events topic
# ---------------------------------------------------------------------------
resource "aws_mskconnect_connector" "snowflake_fraud_events" {
  count = var.enable_msk && var.enable_msk_connect ? 1 : 0
  name  = "medcore-snowflake-fraud-streaming"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 2

      scale_in_policy {
        cpu_utilization_percentage = 20
      }

      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class"                  = "com.snowflake.kafka.connector.SnowflakeSinkConnector"
    "tasks.max"                        = "4"
    "topics"                           = "fraud-events"
    "snowflake.url.name"               = var.snowflake_account_url
    "snowflake.user.name"              = var.snowflake_streaming_user
    "snowflake.private.key"            = var.snowflake_private_key_pem
    "snowflake.database.name"          = "RAW_DB"
    "snowflake.schema.name"            = "STREAMING"
    "snowflake.role.name"              = "STREAMING_INGEST_ROLE"
    "snowflake.ingestion.method"       = "SNOWPIPE_STREAMING"
    "snowflake.enable.schematization"  = "true"
    "buffer.count.records"             = "10000"
    "buffer.flush.time"                = "10"
    "buffer.size.bytes"                = "5000000"
    "key.converter"                    = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable"    = "false"
    "errors.tolerance"                 = "all"
    "errors.deadletterqueue.topic.name"              = "fraud-events-dlq"
    "errors.deadletterqueue.topic.replication.factor" = "2"
    "errors.deadletterqueue.context.headers.enable"  = "true"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_serverless_cluster.fraud_events[0].bootstrap_brokers_sasl_iam

      vpc {
        security_groups = [aws_security_group.msk_connect[0].id]
        subnets         = aws_subnet.streaming[*].id
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.snowflake[0].arn
      revision = aws_mskconnect_custom_plugin.snowflake[0].latest_revision
    }
  }

  worker_configuration {
    arn      = aws_mskconnect_worker_configuration.snowflake[0].arn
    revision = aws_mskconnect_worker_configuration.snowflake[0].latest_revision
  }

  service_execution_role_arn = aws_iam_role.msk_connect[0].arn

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_connect[0].name
      }
    }
  }

  tags = { Chapter = "4" }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}
