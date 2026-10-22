---
name: object-ownership
description: Enforce Chapter 10's one-object-one-owner rule (Table 10.1) before generating any Snowflake object as code. Classify the owner first, generate only in the owning tool, verify with check_ownership.sh.
---

# object-ownership

A CoCo skill that enforces Chapter 10's one rule: one object, one owner.
It encodes Table 10.1 so CoCo classifies every requested Snowflake object
BEFORE generating any code, writes it only in the owning tool's folder, and
verifies the result with a deterministic check instead of a memory.

## When to use

Use this skill whenever a prompt asks to create, manage, or move any
Snowflake object as code in this repository, in any tool. Consult it BEFORE
the `dcm` or `terraform-snowflake-author` skills produce output, and run its
check again as the final step before committing.

## The ownership table (authoritative)

| Object category | Owner | Where it lives |
|-----------------|-------|----------------|
| Warehouses and resource monitors | Terraform | `infra/` |
| Functional roles and account-level grants | Terraform | `infra/` |
| Network policies, integrations, service users | Terraform | `infra/` |
| The operations database and its schemas | Bootstrap + Terraform | `native/bootstrap.sql`, `infra/` |
| Data databases, schemas, tables, views | DCM | `techflow_pipeline/sources/definitions/` |
| Dynamic Tables and tasks | DCM | `techflow_pipeline/sources/definitions/` |
| Shared stream and objects kept outside DCM | Native versioned SQL | `native/` |

## Procedure

1. **Classify first.** Map the requested object to its row in the table.
   If a request spans rows (a warehouse and the Dynamic Table that uses it),
   split the output across the owning tools; never co-locate for convenience.
2. **Reference, never redefine.** When code in one tool needs an object
   owned by another, reference it by name. In DCM, Terraform-owned names come
   in through manifest templating variables (`{{ wh_name }}`), not hardcoded
   and never as a DEFINE.
3. **Refuse two-owner requests.** If asked to define a Terraform-owned object
   in DCM (or the reverse), do not generate it. Explain the rule and offer
   the owner-tool version instead.
4. **Verify deterministically.** After generating, run:

   ```bash
   bash .cortex/skills/object-ownership/check_ownership.sh
   ```

   Exit 0 means no name is managed by both Terraform and DCM. A violation
   prints the colliding names; fix by removing the object from the non-owner,
   never by renaming to dodge the check.

## Why this exists

Two declarative tools that both claim one object will each faithfully undo
the other on every run: the warehouse flips its size on every deploy and the
plans never converge. The check is scoped to Terraform vs DCM because those
two reconcile state; `native/` scripts are one-time steps, the shared stream, and scripts for
unsupported types, and do not fight another tool.

## Limitations

The check also rejects DEFINE STREAM in this chapter, where native SQL retains the shared stream. It compares identifier names, not full configurations, and it can
surface a false positive if an unrelated schema-level object shares a name
with an account-level one. Treat its output as a review list: every hit needs
a human decision, and passing does not replace `terraform plan` and
`snow dcm plan` before deploying.
