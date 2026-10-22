---
name: terraform-snowflake-author
description: Generate Snowflake Terraform (HCL) for account-level infrastructure (warehouses, roles, grants, integrations) following Chapter 10 patterns. Not for schema-level pipeline objects, which belong to the dcm skill.
---

# terraform-snowflake-author

A CoCo skill for generating Snowflake Terraform (HCL) resources for
account-level infrastructure, following the patterns in Chapter 10
(Section 4.4). It complements CoCo's bundled `dcm` skill: the `dcm` skill
authors pipeline objects, this one authors the account scaffolding around them.

## When to use

Use this skill when prompted to manage Snowflake account infrastructure as
code: warehouses, databases, functional roles, account-level grants, resource
monitors, network policies, or integrations. Do not use it for schema-level
pipeline objects (schemas, tables, Dynamic Tables, tasks) - those belong to
the `dcm` skill.

## Design rules encoded

1. **Official provider only.** Always constrain `snowflakedb/snowflake` with a
   `~> 2.0` constraint. Never generate the retired `Snowflake-Labs/snowflake`
   provider.
2. **Version-2 resource names.** Use `snowflake_account_role` (not
   `snowflake_role`) and `snowflake_grant_privileges_to_account_role` for
   account grants. The provider renamed these in the move to version 2.
3. **Key-pair authentication.** Configure `authenticator = "SNOWFLAKE_JWT"`
   and read the key from a file or the `SNOWFLAKE_PRIVATE_KEY` env var. Never
   generate a password field or inline a key.
4. **Explicit least-privilege role.** Always set `role` in the provider block
   so Terraform runs under a scoped role, not the user's default.
5. **References over ordering.** Wire dependencies by referencing other
   resources' attributes (`snowflake_warehouse.x.name`) so Terraform builds
   the dependency graph itself. Never hand-order resources.
6. **No secrets in code.** Connection details and keys come from variables or
   environment, never hardcoded (Rules 2 and 9 of secure development).

## One-object-one-owner review (critical)

Because two infrastructure tools are in play, the failure mode is CoCo
generating both a Terraform `snowflake_warehouse` resource and a DCM
`DEFINE WAREHOUSE` statement for the same object, leaving each tool to undo
the other on every run. Before committing anything this skill generates,
confirm against Table 10.1:

1. Each object appears in exactly one tool.
2. Account-level infrastructure (warehouses, databases, roles, grants,
   network policies, integrations) landed in Terraform.
3. Pipeline objects (schemas, tables, Dynamic Tables, tasks) landed in DCM.
4. No warehouse or role is defined in both places.

## Example prompt

> Using the terraform-snowflake-author skill, generate the account
> infrastructure for the TechFlow pipeline: the `BOOK_WH` XSMALL warehouse, a
> `TRANSFORMER` functional role, and a grant giving the role USAGE and OPERATE
> on the warehouse. Authenticate with key-pair auth via environment variables.

## Limitations

This skill generates HCL for review. It does not run `terraform apply`. Always
review generated resources against the one-object-one-owner checklist and run
`terraform plan` before applying.
