terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment after running setup/terraform/backend first:
  # backend "s3" {
  #   bucket         = "snowflake-book-tfstate-<YOUR_SUFFIX>"
  #   key            = "aws/terraform.tfstate"
  #   region         = "ca-central-1"
  #   dynamodb_table = "snowflake-book-tflock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
  # Named profile: export AWS_PROFILE=... (same as aws CLI).
  skip_metadata_api_check = true
  # Force standard file locations (some setups don’t resolve ~/.aws via the SDK default chain).
  shared_credentials_files = fileexists(pathexpand("~/.aws/credentials")) ? [pathexpand("~/.aws/credentials")] : null
  shared_config_files      = fileexists(pathexpand("~/.aws/config")) ? [pathexpand("~/.aws/config")] : null
}

locals {
  bucket_name = "medcore-lakehouse-${var.bucket_suffix}"

  use_snowflake_ext_vol_trust = var.snowflake_ext_vol_iam_arn != ""
  use_snowflake_glue_trust    = var.snowflake_glue_iam_arn != ""
  use_snowflake_s3t_trust     = var.snowflake_s3tables_iam_arn != ""
  use_snowflake_stage_trust   = var.snowflake_stage_iam_arn != ""

  # IGW + public subnet for WireGuard ECS, SSH bastion, or NAT for MSK Connect egress.
  streaming_public_network = var.enable_msk && (var.enable_vpn || var.enable_bastion || var.enable_msk_connect)
}

# ---------------------------------------------------------------------------
# S3 bucket for Iceberg data
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "medcore_lakehouse" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "medcore_lakehouse" {
  bucket = aws_s3_bucket.medcore_lakehouse.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "medcore_lakehouse" {
  bucket = aws_s3_bucket.medcore_lakehouse.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "medcore_lakehouse" {
  bucket                  = aws_s3_bucket.medcore_lakehouse.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "medcore_lakehouse" {
  bucket = aws_s3_bucket.medcore_lakehouse.id

  rule {
    id     = "expire-old-iceberg-snapshots"
    status = "Enabled"
    filter {
      prefix = "iceberg/"
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ---------------------------------------------------------------------------
# IAM role: Snowflake external volume (S3 read/write)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "snowflake_iceberg_role" {
  name = "SnowflakeIcebergRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.use_snowflake_ext_vol_trust ? {
        Effect    = "Allow"
        Principal = { AWS = var.snowflake_ext_vol_iam_arn }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "sts:ExternalId" = var.snowflake_ext_vol_ext_id }
        }
        } : {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "sts:ExternalId" = "placeholder-run-phase2" } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "snowflake_s3_access" {
  name = "SnowflakeS3Access"
  role = aws_iam_role.snowflake_iceberg_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.medcore_lakehouse.arn,
          "${aws_s3_bucket.medcore_lakehouse.arn}/*"
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM role: Snowflake Glue catalog integration
# ---------------------------------------------------------------------------
resource "aws_iam_role" "snowflake_glue_role" {
  name = "SnowflakeGlueRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.use_snowflake_glue_trust ? {
        Effect    = "Allow"
        Principal = { AWS = var.snowflake_glue_iam_arn }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "sts:ExternalId" = var.snowflake_glue_ext_id }
        }
        } : {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "sts:ExternalId" = "placeholder-run-phase2" } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "snowflake_glue_access" {
  name = "SnowflakeGlueAccess"
  role = aws_iam_role.snowflake_glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetCatalog",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetDatabase",
          "glue:GetDatabases"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:database/clinical_research",
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:table/clinical_research/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.medcore_lakehouse.arn,
          "${aws_s3_bucket.medcore_lakehouse.arn}/*"
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM role: Snowflake S3 Tables catalog integration
# ---------------------------------------------------------------------------
resource "aws_iam_role" "snowflake_s3tables_role" {
  name = "SnowflakeS3TablesRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.use_snowflake_s3t_trust ? {
        Effect    = "Allow"
        Principal = { AWS = var.snowflake_s3tables_iam_arn }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "sts:ExternalId" = var.snowflake_s3tables_ext_id }
        }
        } : {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "sts:ExternalId" = "placeholder-run-phase2" } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "snowflake_s3tables_access" {
  name = "SnowflakeS3TablesAccess"
  role = aws_iam_role.snowflake_s3tables_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3tables:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM role: Snowflake storage integration for external stages (Ch.3, Ch.8)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "snowflake_stage_role" {
  name = "SnowflakeStageRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.use_snowflake_stage_trust ? {
        Effect    = "Allow"
        Principal = { AWS = var.snowflake_stage_iam_arn }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "sts:ExternalId" = var.snowflake_stage_ext_id }
        }
        } : {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "sts:ExternalId" = "placeholder-run-phase2" } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "snowflake_stage_access" {
  name = "SnowflakeStageAccess"
  role = aws_iam_role.snowflake_stage_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.medcore_lakehouse.arn,
          "${aws_s3_bucket.medcore_lakehouse.arn}/*"
        ]
      }
    ]
  })
}
