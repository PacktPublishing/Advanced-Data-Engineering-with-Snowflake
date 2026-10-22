// =====================================================================
// Chapter 10: Provider connection variables
// =====================================================================
// Defaults match the chapter's TECHFLOW / MAIN / TERRAFORM_DEPLOYER naming.
// Override via terraform.tfvars (git-ignored) or SNOWFLAKE_* environment
// variables for a hands-on run against your own account.
// =====================================================================

variable "organization_name" {
  type        = string
  default     = null
  description = "Snowflake organization name (env: SNOWFLAKE_ORGANIZATION_NAME)."
}

variable "account_name" {
  type        = string
  default     = null
  description = "Snowflake account name (env: SNOWFLAKE_ACCOUNT_NAME). Chapter uses MAIN."
}

variable "snowflake_user" {
  type        = string
  default     = null
  description = "Service user for automation (env: SNOWFLAKE_USER)."
}

variable "snowflake_role" {
  type        = string
  default     = "TERRAFORM_DEPLOYER"
  description = "Least-privilege role Terraform operates under (created by native/bootstrap.sql)."
}

variable "private_key_path" {
  type        = string
  default     = null
  description = "Path to the PEM private key file for key-pair auth. Supports ~ via pathexpand(). Leave null in CI and set SNOWFLAKE_PRIVATE_KEY with the key content instead."
}

variable "warehouse_size" {
  type        = string
  default     = "XSMALL"
  description = "Size for the transform warehouse."
}
