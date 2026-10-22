# Chapter 3 companion

Scripts for batch data ingestion patterns on the MedCore lakehouse.

## Database

**`MEDCORE_DEMO`** — assumes Chapter 2 objects exist. Run [chapter2_scripts.sql](../chapter2/chapter2_scripts.sql) first if you are starting here.

## Run order

1. Complete [setup/SETUP.md](../../setup/SETUP.md) and Chapter 2.
2. Run [chapter3_scripts.sql](chapter3_scripts.sql) section by section in Snowsight or with `snow sql -c book -f chapter3_scripts.sql`.

## Next chapter

[Chapter 4](../chapter4/README.md) introduces the TechFlow **`RAW_DB`** / **`SILVER_DB`** medallion. Create those databases (or adjust names) before running Chapter 4 scripts.
