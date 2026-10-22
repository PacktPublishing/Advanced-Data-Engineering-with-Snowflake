-- =============================================================================
-- Chapter 3 — chapter3_resize_files.sql
-- Re-shape badly sized source files into the 100-250MB target using Snowflake
-- itself: split one oversized file on the way out (COPY INTO <location> with
-- MAX_FILE_SIZE), and pre-merge thousands of tiny files by loading them into a
-- pass-through table and unloading once.
-- Referenced from the chapter's "Optimizing File Size for the 100-250MB Rule"
-- section.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;
USE SCHEMA MEDCORE_DEMO.STAGING;

-- -----------------------------------------------------------------------------
-- Case 1: one oversized file, split into correctly sized files
-- Load the large file into a pass-through table, then unload with
-- MAX_FILE_SIZE (bytes). Snowflake splits the output into files under that
-- ceiling; 200 MB compressed lands inside the 100-250MB target.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE _resize_passthrough (raw VARIANT);

COPY INTO _resize_passthrough
FROM (SELECT $1 FROM @medcore_s3_stage/oversized/)
    FILE_FORMAT = (TYPE = PARQUET);

-- HEADER = TRUE keeps the real column names in the unloaded Parquet
COPY INTO @medcore_s3_stage/resized/
FROM _resize_passthrough
    FILE_FORMAT = (TYPE = PARQUET)
    MAX_FILE_SIZE = 209715200   -- 200 MB
    HEADER = TRUE;

-- Verify: every output file sits at or under the ceiling
LIST @medcore_s3_stage/resized/;

-- -----------------------------------------------------------------------------
-- Case 2: thousands of tiny files, merged into a few well-sized files
-- Same pass-through in the opposite direction: one parallel COPY pulls every
-- tiny file, one unload writes a handful of 200 MB files.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE _merge_passthrough (raw VARIANT);

COPY INTO _merge_passthrough
FROM (SELECT $1 FROM @medcore_s3_stage/tiny_files/)
    FILE_FORMAT = (TYPE = PARQUET);

COPY INTO @medcore_s3_stage/merged/
FROM _merge_passthrough
    FILE_FORMAT = (TYPE = PARQUET)
    MAX_FILE_SIZE = 209715200
    HEADER = TRUE;

LIST @medcore_s3_stage/merged/;

-- Clean up
DROP TABLE IF EXISTS _resize_passthrough;
DROP TABLE IF EXISTS _merge_passthrough;
