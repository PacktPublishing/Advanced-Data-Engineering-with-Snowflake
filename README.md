# Advanced Snowflake Data Engineering

Companion code for *Advanced Snowflake Data Engineering: A Hands-On Guide to Ingest, Transform, Orchestrate, and Govern Data with Iceberg, dbt, and Cortex AI* (Packt, ISBN 9781807608736): SQL, Python, Terraform, dbt, and orchestration examples that match the book exercises.

## Where to start

1. **[setup/SETUP.md](setup/SETUP.md)** — Snowflake bootstrap, optional AWS/Azure infrastructure, Snowflake CLI connection `book`.
2. Run each chapter in order using that chapter's README (scripts, teardown, and prerequisites).
3. **[setup/TESTING.md](setup/TESTING.md)** — optional end-to-end checklist for Terraform, MSK, and Chapter 4 streaming.

## Databases and naming

| Chapters | Primary databases / scope |
|----------|---------------------------|
| 2–3 | `MEDCORE_DEMO` (lakehouse and batch ingestion labs) |
| 4+ | `RAW_DB`, `SILVER_DB`, and `GOLD_DB` medallion (TechFlow), plus chapter-specific databases |

From Chapter 4 onward, most hands-on work builds on the shared medallion. Individual chapters also create or use dedicated databases (for example `OPS_DB`, governance and vault schemas, analytics serving, multi-tenant control planes, and listing/clean-room fixtures). Each chapter README lists the objects that chapter owns.

## Chapter index

Chapter 1 has no companion code in this repository.

| Chapter | Folder | Guide |
|---------|--------|--------|
| 2 | [chapters/chapter2](chapters/chapter2) | [README](chapters/chapter2/README.md) |
| 3 | [chapters/chapter3](chapters/chapter3) | [README](chapters/chapter3/README.md) |
| 4 | [chapters/chapter4](chapters/chapter4) | [README](chapters/chapter4/README.md) |
| 5 | [chapters/chapter5](chapters/chapter5) | [README](chapters/chapter5/README.md) |
| 6 | [chapters/chapter6](chapters/chapter6) | [README](chapters/chapter6/README.md) |
| 7 | [chapters/chapter7](chapters/chapter7) | [README](chapters/chapter7/README.md) |
| 8 | [chapters/chapter8](chapters/chapter8) | [README](chapters/chapter8/README.md) |
| 9 | [chapters/chapter9](chapters/chapter9) | [README](chapters/chapter9/README.md) |
| 10 | [chapters/chapter10](chapters/chapter10) | [README](chapters/chapter10/README.md) |
| 11 | [chapters/chapter11](chapters/chapter11) | [README](chapters/chapter11/README.md) |
| 12 | [chapters/chapter12](chapters/chapter12) | [README](chapters/chapter12/README.md) |
| 13 | [chapters/chapter13](chapters/chapter13) | [README](chapters/chapter13/README.md) |
| 14 | [chapters/chapter14](chapters/chapter14) | [README](chapters/chapter14/README.md) |
| 15 | [chapters/chapter15](chapters/chapter15) | [README](chapters/chapter15/README.md) |
| 16 | [chapters/chapter16](chapters/chapter16) | [README](chapters/chapter16/README.md) |
| 17 | [chapters/chapter17](chapters/chapter17) | [README](chapters/chapter17/README.md) |
| 18 | [chapters/chapter18](chapters/chapter18) | [README](chapters/chapter18/README.md) |
| 19 | [chapters/chapter19](chapters/chapter19) | [README](chapters/chapter19/README.md) |

## Terraform (shared setup)

Run Terraform from **`setup/terraform/aws`** (not the repo root). Copy `terraform.tfvars.example` to `terraform.tfvars` and set your account id, bucket suffix, and (when enabling VPN or bastion) your public IP CIDRs. Details are in [setup/SETUP.md](setup/SETUP.md).

## Trial accounts

Many chapters run on a Snowflake trial. External Access Integration, OpenFlow, Cortex, listings, and similar features may require a paid edition or account flags. Each chapter README calls out what to skip on trial.

## Repo layout

```
setup/           Snowflake bootstrap, SETUP.md, TESTING.md, terraform/
chapters/        chapter2 … chapter19 companion code
tools/           check_path_alignment.py (README path guard)
.github/         Chapter 6 CI and path-alignment workflow
```
