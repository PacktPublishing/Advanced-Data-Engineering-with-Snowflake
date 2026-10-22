# Chapter 10 Infrastructure-as-Code Project Rules

## Project Overview
Turns the Chapter 9 TechFlow pipeline into managed, versioned, deployable
code. Architecture order matches the chapter (September 2026 revision):

- `native/`   - CREATE OR ALTER, Git integration, bootstrap roles (Section 1–2.1)
- `infra/`    - Terraform for account scaffolding (Section 2)
- `techflow_pipeline/` - DCM Project for pipeline objects (Section 3)
- `migrations/` - legacy reference only; not part of the chapter exercise
- `cicd/`     - GitHub Actions plan-on-PR / re-plan-then-deploy (Section 4)
- `.cortex/skills/terraform-snowflake-author/` - CoCo skill for HCL
- `.cortex/skills/object-ownership/` - CoCo skill enforcing Table 10.1 + check script

## Tech Stack
- Snowflake SQL (CREATE OR ALTER, Git repository objects, EXECUTE IMMEDIATE FROM)
- Snowflake CLI (`snow`) 3.26.0; no legacy project feature flag
- DCM Projects (manifest v2, DEFINE, `env_suffix` templating) - GA; DEFINE STREAM remains open preview
- Terraform CLI 1.14.4 and `snowflakedb/snowflake` provider `~> 2.0`
- Legacy migration examples are reference-only and excluded from active CI
- GitHub Actions, key-pair (`SNOWFLAKE_JWT`) auth only
- Databases: `raw_db` (shared), `silver_db`/`gold_db` (+ `_DEV` suffix), `ops_db`
- Warehouse: `BOOK_WH` (Terraform-owned, imported from Chapter 9)

## The one rule that matters: one object, one owner
Never let two tools manage the same object (Table 10.1). Before generating any
Snowflake object, consult `.cortex/skills/object-ownership/SKILL.md` and run
`.cortex/skills/object-ownership/check_ownership.sh` after generating; CI runs
the same check on every pull request.

| Object category | Owner |
|-----------------|-------|
| Warehouses and resource monitors | Terraform |
| Functional roles and account-level grants | Terraform |
| Network policies, integrations, service users | Terraform |
| The operations database and its schemas | Terraform / bootstrap |
| Data databases, schemas, tables, views | DCM |
| Dynamic Tables and tasks | DCM |
| Shared stream and objects kept outside DCM | Native SQL scripts (`native/`) |

Warehouse and roles are **not** defined in DCM. `00_account.sql` was removed
on purpose. DCM references `BOOK_WH`; Terraform owns it.

## Coding Standards
- Authenticate with key pairs (`SNOWFLAKE_JWT`), never passwords.
- Bootstrap (`native/bootstrap.sql`) runs once as ACCOUNTADMIN; everything
  after uses `TERRAFORM_DEPLOYER`, `DCM_DEVELOPER`, or `DCM_PROD_DEPLOYER`.
- Terraform: pin `snowflakedb/snowflake` `~> 2.0`, use version-2 resource
  names, `pathexpand()` for key paths, commit `.terraform.lock.hcl`, import
  existing `BOOK_WH` before first apply.
- DCM: only DEFINE / GRANT / ATTACH. Template object names with `{{ env_suffix }}` and warehouse references with `{{ wh_name }}`.
  Shared raw layer is unsuffixed and defined only for PROD; DEV references it. Removing a DEFINE drops the object.
- Native SQL retains the shared stream while DEFINE STREAM is preview.
  Never define it in both DCM targets or run the legacy migration in active CI.
- CI deploy order: Terraform → native stream SQL → DCM. Re-plan PROD before apply.

## Don'ts
- Never define the same object in two tools.
- Never put a `DEFINE WAREHOUSE` back into the DCM project.
- Never commit Terraform state, `.tfvars`, private keys, or DCM `out/`/`output/`.
- Never apply to PROD without a reviewed PROD plan and environment approval.
