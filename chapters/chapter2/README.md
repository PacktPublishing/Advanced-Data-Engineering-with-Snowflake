# Chapter 2 companion

Scripts for the MedCore lakehouse chapter: external volumes, Iceberg, and related Snowflake objects.

## Database

**`MEDCORE_DEMO`** — created and used throughout [chapter2_scripts.sql](chapter2_scripts.sql).

## Run order

1. Complete [setup/SETUP.md](../../setup/SETUP.md) (Snowflake bootstrap and, if you follow the AWS sections, Terraform outputs for the external volume).
2. Run [chapter2_scripts.sql](chapter2_scripts.sql) **section by section** in Snowsight or with `snow sql -c book -f chapter2_scripts.sql` after replacing every `<REPLACE: …>` placeholder in each section.

## Next chapter

[Chapter 3](../chapter3/README.md) continues batch ingestion patterns in the same `MEDCORE_DEMO` database.
