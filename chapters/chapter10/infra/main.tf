// =====================================================================
// Chapter 10, Section 2.3: Warehouses, roles, and grants in HCL
// =====================================================================
// Terraform owns the account scaffolding the data team depends on but rarely
// changes: the compute, the functional roles, and the grants that connect
// them (Table 10.1). DCM owns the schema-level pipeline objects.
//
// Resource names use the version-2 provider vocabulary:
//   * snowflake_account_role (not the old snowflake_role)
//   * snowflake_grant_privileges_to_account_role
// When the grant references the warehouse and role by name, Terraform builds
// its dependency graph from those references and creates them in order, so
// you never write ordering logic.
// =====================================================================

resource "snowflake_warehouse" "book_wh" {
  name           = "BOOK_WH"
  warehouse_size = var.warehouse_size
  auto_suspend   = 60
  auto_resume    = true
  comment        = "Transform compute for the TechFlow pipeline"
}

resource "snowflake_account_role" "transformer" {
  name    = "TRANSFORMER"
  comment = "Owns the TechFlow transformation pipeline"
}

resource "snowflake_grant_privileges_to_account_role" "book_wh_usage" {
  privileges        = ["USAGE", "OPERATE"]
  account_role_name = snowflake_account_role.transformer.name

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.book_wh.name
  }
}
