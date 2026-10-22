// =====================================================================
// Chapter 10, Section 2.2: Provider requirements
// =====================================================================
// Constrain the official snowflakedb/snowflake provider. The retired
// Snowflake-Labs/snowflake provider must not be used for new work. The
// ~> 2.0 constraint allows patch and minor updates within version 2 but
// blocks an automatic jump to a future version 3 that could change resource names or behavior.
// The committed lock file fixes the selected provider build.
// Static validation for this revision uses Terraform CLI 1.14.4.
// =====================================================================

terraform {
  required_version = ">= 1.9"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
}
