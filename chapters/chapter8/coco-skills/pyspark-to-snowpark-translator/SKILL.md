---
name: pyspark-to-snowpark-translator
description: Translate a single PySpark job to run on Snowpark Connect for Spark. Encodes the Chapter 8 compatibility gaps and cleanup rules, and flags rather than silently rewrites anything with no direct equivalent.
---

# When to Use

Use when migrating one PySpark or Spark SQL job onto Snowpark Connect with the
smallest diff (a rehost, not a rewrite). Scope is always a single file. For
estate-wide conversion that produces a new native-Snowpark codebase, use
SnowConvert AI (Chapter 17), not this skill.

Copy the parent `coco-skills/` directory into `~/.snowflake/cortex/skills/`
once after Chapter 6, refresh with `/skill sync`, and confirm with
`/skill list`. Invoke with the `$pyspark-to-snowpark-translator` prefix.

# What This Skill Provides

- A rehost translation that keeps the DataFrame API surface intact
- The Section 2.2 compatibility gaps pinned so the agent flags them
- The Section 5.1 cleanup list (dead tuning removed, not carried over)
- A flag-don't-rewrite contract for anything ambiguous or unsupported

# Instructions

1. Read the named file only. Never accept "convert all my Spark code"; demand a
   single-file scope so the diff stays reviewable.
2. Keep the DataFrame API surface. The goal is the smallest diff, not idiomatic
   native Snowpark.
3. Redirect `s3a://` / `gs://` / `abfss://` reads to `@<stage>` paths
   (Section 4.1). Route Avro and ORC reads through an external table
   (Section 4.2), never `spark.read.format("avro")`.
4. Rework `Append` and `Ignore` save modes: write to a Snowflake table, or
   restructure to a dated overwrite path. These modes are not supported on
   Parquet, CSV, or JSON file writes.
5. Remove `hint()`, `repartition()`, `coalesce()`, `cache()`, and `persist()`.
   They are accepted-and-ignored or no-ops; map the intent onto warehouse
   sizing or a materialized temp table, not onto a dropped call.
6. FLAG, do not silently rewrite:
   - any API with no Snowpark Connect equivalent (RDD, `pyspark.ml`,
     `pyspark.streaming`, iterator UDFs, UDFs inside lambdas);
   - any UDF whose semantics change (`StructType` arrives as a `dict` keyed
     `_1`, `_2`, not a positional tuple; `NULL` vs `None` handling when a UDF
     becomes a `CASE`);
   - any type coercion that affects output columns (`ByteType`/`ShortType`/
     `IntegerType` come back `LongType`; `lit(None)` infers `StringType`).
7. After translating, diff the original output schema against the translated
   version column by column, with the type coercions called out explicitly.

# Failure Modes to Self-Check

- A dropped `cache()` on a DataFrame consumed by two branches: correct output,
  doubled cost. Replace with a temp table written once and read twice.
- A broadcast join becoming a different strategy under the Snowflake optimizer:
  almost always fine, occasionally a regression on a skewed key. Surface it for
  a Query Profile review.
- A UDF rewritten to a `CASE` that returns `NULL` where the original returned a
  default string. Flag the null path for the reviewer.

# Example

Input (`jobs/merchant_rollup.py`, excerpt):

```python
df = spark.read.parquet("s3a://techflow-lake/merchants/2026/06/")
df = df.repartition(200).hint("broadcast")
out = df.groupBy("merchant_id").count()
out.write.mode("Append").parquet("s3a://techflow-lake/rollups/")
```

Output (rehosted, with flags):

```python
# FLAG: Append save mode unsupported on file writes; rewritten to overwrite a
#       Snowflake table. Confirm no downstream reader depends on appended files.
df = spark.read.parquet("@lake_stage/merchants/2026/06/")
# Removed repartition(200) and hint("broadcast"): no-ops on Snowflake.
out = df.groupBy("merchant_id").count()
out.write.mode("overwrite").saveAsTable("gold_db.transactions.merchant_rollup")
```
