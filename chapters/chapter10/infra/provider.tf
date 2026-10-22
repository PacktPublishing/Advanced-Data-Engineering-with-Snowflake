// =====================================================================
// Chapter 10, Section 2.2: Configuring the Snowflake provider
// =====================================================================
// Automation authenticates with a key pair under TERRAFORM_DEPLOYER (created
// by native/bootstrap.sql), not SYSADMIN. private_key uses pathexpand()
// because Terraform's file() does not expand the tilde on its own.
//
// Every field can also come from a matching environment variable
// (SNOWFLAKE_ORGANIZATION_NAME, SNOWFLAKE_ACCOUNT_NAME, SNOWFLAKE_USER,
// SNOWFLAKE_PRIVATE_KEY, ...), which is how the CI pipeline supplies the
// connection without hardcoding it.
// =====================================================================

provider "snowflake" {
  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.snowflake_user
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = var.private_key_path != null ? file(pathexpand(var.private_key_path)) : null
  role              = var.snowflake_role
}
