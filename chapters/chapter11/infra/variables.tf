variable "aws_region" {
  type    = string
  default = "ca-central-1"
}

variable "aws_account_id" {
  description = "Your AWS account ID (12 digits)"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket for Chapter 11 fraud scores. Must be globally unique."
  type        = string
  default     = "techflow-ml"
}

variable "snowflake_stage_iam_arn" {
  description = "STORAGE_AWS_IAM_USER_ARN from DESC STORAGE INTEGRATION techflow_ml_integration"
  type        = string
  default     = ""
}

variable "snowflake_stage_ext_id" {
  description = "STORAGE_AWS_EXTERNAL_ID from DESC STORAGE INTEGRATION techflow_ml_integration"
  type        = string
  default     = ""
}
