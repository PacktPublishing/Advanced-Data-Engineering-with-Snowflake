# Chapter 10 validation — September 2026 review

Checked on 13 September 2026. This revision was validated locally; no Snowflake
account, remote Terraform state, or GitHub deployment was changed.

## Selected versions

- Terraform CLI 1.14.4.
- `snowflakedb/snowflake` provider 2.21.0, constrained by `~> 2.0` and selected
  in `infra/.terraform.lock.hcl`. Provider checksums were fetched for Darwin
  ARM64 and Linux AMD64 using `terraform providers lock`.
- Snowflake CLI 3.26.0 installed in an isolated Python 3.12 environment.

## Checks completed

| Check | Result |
|---|---|
| `terraform fmt -check -diff` | Passed |
| Isolated `terraform init -backend=false`, then `terraform validate -json` | Passed: zero errors and zero warnings against provider 2.21.0 |
| Installed CLI command help | Confirmed options used by DCM plan/deploy and SQL file execution |
| Manifest parsing using CLI 3.26.0's `DCMManifest.from_dict` | Accepted manifest v2 and both targets |
| Strict Jinja rendering of all three definition files for DEV and PROD | Passed, with no unresolved template variables |
| Cross-target object names | Eight DEV and eleven PROD objects; no name overlap; shared raw definitions appear only in PROD |
| Warehouse references | Rendered DCM definitions reference BOOK_WH without defining it |
| Ownership guard | Existing examples pass; isolated duplicate BOOK_WH and DEFINE STREAM injections both fail as expected |
| Both workflow YAML templates | Parsed successfully; working directories and referenced script paths exist |
| Workflow shell syntax | All 20 run blocks passed `bash -n` after replacing GitHub expressions with test placeholders |
| Workflow structure | Tool versions, separate CI/PROD key secrets, artifact paths, triggering-commit checkout, production dependency/gate, cleanup and deployment order checked |
| Legacy migration | Original SQL bytes retained; README identifies it as reference only; no migration runner in either workflow |

Terraform validation checks configuration against the installed provider
schema. Jinja rendering and manifest parsing do not validate Snowflake SQL on
the server. YAML and shell checks do not prove a hosted workflow succeeds.

## Before a live walkthrough

Complete the account-specific setup in the README: Chapter 9 objects, service
users and grants, DCM projects, imported shared Terraform state, and GitHub
environment protection. Run DEV and PROD plans and review adoption changes
before applying anything. The YAML environment name alone is not an approval
rule; required reviewers must be configured in GitHub.

If an older DEV project already manages shared raw objects, follow Snowflake's
DCM unmanage procedure before adopting this PROD-only raw definition layout.
Removing a managed definition without that handoff can propose a drop. The
native stream script preserves an existing stream but does not reconcile its
properties. These account-dependent behaviors were not execution-tested here.
