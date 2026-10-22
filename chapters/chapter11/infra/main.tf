locals {
  scores_prefix             = "scores/"
  use_snowflake_stage_trust = var.snowflake_stage_iam_arn != ""
}

resource "aws_s3_bucket" "techflow_ml" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "techflow_ml" {
  bucket = aws_s3_bucket.techflow_ml.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "techflow_ml" {
  bucket = aws_s3_bucket.techflow_ml.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "techflow_ml" {
  bucket                  = aws_s3_bucket.techflow_ml.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "scores_prefix" {
  bucket = aws_s3_bucket.techflow_ml.id
  key    = local.scores_prefix
}

resource "aws_iam_role" "techflow_ml" {
  name = "techflow-ml-role"

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

resource "aws_iam_role_policy" "techflow_ml_scores" {
  name = "TechflowMlScoresAccess"
  role = aws_iam_role.techflow_ml.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.techflow_ml.arn}/${local.scores_prefix}*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.techflow_ml.arn
        Condition = {
          StringLike = { "s3:prefix" = ["${local.scores_prefix}*"] }
        }
      }
    ]
  })
}
