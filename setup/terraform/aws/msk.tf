# ---------------------------------------------------------------------------
# Chapter 4: MSK Serverless + Kinesis Data Stream
# Gated behind enable_msk / enable_kinesis variables (default: false).
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------------------------------------------------------------------
# VPC (shared by MSK Serverless — created only when enable_msk = true)
# ---------------------------------------------------------------------------
resource "aws_vpc" "streaming" {
  count      = var.enable_msk ? 1 : 0
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "medcore-streaming-vpc" }
}

resource "aws_subnet" "streaming" {
  count             = var.enable_msk ? 2 : 0
  vpc_id            = aws_vpc.streaming[0].id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "medcore-streaming-${count.index}" }
}

resource "aws_security_group" "msk" {
  count       = var.enable_msk ? 1 : 0
  name_prefix = "medcore-msk-"
  description = "Allow Kafka IAM traffic for MSK Serverless"
  vpc_id      = aws_vpc.streaming[0].id

  ingress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.streaming[0].cidr_block]
    description = "Kafka IAM auth"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "medcore-msk-sg" }
}

# ---------------------------------------------------------------------------
# NAT gateway — MSK Connect workers in private subnets need HTTPS to Snowflake
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.enable_msk && var.enable_msk_connect ? 1 : 0
  domain = "vpc"

  tags = { Name = "medcore-msk-nat" }
}

resource "aws_nat_gateway" "streaming" {
  count         = var.enable_msk && var.enable_msk_connect ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.streaming_public[0].id

  tags = { Name = "medcore-streaming-nat" }

  depends_on = [aws_internet_gateway.streaming]
}

resource "aws_route_table" "streaming_private" {
  count  = var.enable_msk && var.enable_msk_connect ? 1 : 0
  vpc_id = aws_vpc.streaming[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.streaming[0].id
  }

  tags = { Name = "medcore-streaming-private-rt" }
}

resource "aws_route_table_association" "streaming_private" {
  count          = var.enable_msk && var.enable_msk_connect ? min(length(aws_subnet.streaming), 2) : 0
  subnet_id      = aws_subnet.streaming[count.index].id
  route_table_id = aws_route_table.streaming_private[0].id
}

# ---------------------------------------------------------------------------
# MSK Serverless cluster
# ---------------------------------------------------------------------------
resource "aws_msk_serverless_cluster" "fraud_events" {
  count        = var.enable_msk ? 1 : 0
  cluster_name = "medcore-fraud-events"

  vpc_config {
    subnet_ids         = aws_subnet.streaming[*].id
    security_group_ids = [aws_security_group.msk[0].id]
  }

  client_authentication {
    sasl {
      iam { enabled = true }
    }
  }

  tags = { Chapter = "4" }
}

# ---------------------------------------------------------------------------
# Kinesis Data Stream (for OpenFlow Connector for Kinesis exercise)
# ---------------------------------------------------------------------------
resource "aws_kinesis_stream" "fraud_events" {
  count = var.enable_kinesis ? 1 : 0
  name  = "fraud-events"

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  retention_period = 24

  tags = { Chapter = "4" }
}

# IAM user for the OpenFlow Kinesis connector (requires Access Key auth)
resource "aws_iam_user" "kinesis_connector" {
  count = var.enable_kinesis ? 1 : 0
  name  = "snowflake-kinesis-connector"
  path  = "/book/"

  tags = { Chapter = "4" }
}

resource "aws_iam_user_policy" "kinesis_connector" {
  count = var.enable_kinesis ? 1 : 0
  name  = "KinesisConnectorAccess"
  user  = aws_iam_user.kinesis_connector[0].name

  # Matches the example policy in the Openflow Kinesis connector setup docs.
  # The DynamoDB table name is the connector's "AWS Kinesis Application Name"
  # parameter (Block 7 of chapter4_openflow_setup.sql uses techflow_fraud_events).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KinesisStreamAccess"
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamConsumer",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards",
          "kinesis:RegisterStreamConsumer"
        ]
        Resource = aws_kinesis_stream.fraud_events[0].arn
      },
      {
        Sid    = "KinesisConsumerAccess"
        Effect = "Allow"
        Action = [
          "kinesis:DeregisterStreamConsumer",
          "kinesis:DescribeStreamConsumer",
          "kinesis:SubscribeToShard"
        ]
        Resource = "${aws_kinesis_stream.fraud_events[0].arn}/consumer/*"
      },
      {
        Sid    = "DynamoDBTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.kinesis_application_name}",
          "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.kinesis_application_name}_migration"
        ]
      }
    ]
  })
}

resource "aws_iam_access_key" "kinesis_connector" {
  count = var.enable_kinesis ? 1 : 0
  user  = aws_iam_user.kinesis_connector[0].name
}
