// =====================================================================
// Chapter 10: Outputs
// =====================================================================
// Surface the names Terraform created so downstream tooling (DCM, docs,
// other Terraform modules) can reference them without hardcoding.
// =====================================================================

output "warehouse_name" {
  value       = snowflake_warehouse.book_wh.name
  description = "Name of the transform warehouse Terraform manages."
}

output "transformer_role_name" {
  value       = snowflake_account_role.transformer.name
  description = "Functional role that owns the TechFlow transformation pipeline."
}
