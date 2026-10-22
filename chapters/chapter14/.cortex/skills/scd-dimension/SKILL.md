---
name: scd-dimension
description: Generate MERGE-based Slowly Changing Dimension loads (Type 1, Type 2 batch close-and-insert, Type 3) and their invariant checks for the TechFlow gold layer, plan-first, following AGENTS.md conventions. Use when asked to build, extend, or review an SCD load for a dimension.
---

# When to Use

- A new or changed dimension needs a Type 1, Type 2, or Type 3 load from a
  staging table.
- An existing SCD load needs review against the conventions in `AGENTS.md`.
- Someone asks for the invariant checks that prove a Type 2 dimension is
  consistent.

Do not use it for stream-fed Type 2 loads (the Chapter 5 stable-delta pattern
with a temp table) unless the prompt says the source is a stream; the batch
shape below assumes a stable staging table.

# What This Skill Provides

1. A plan file, `plans/<dimension>_scd<type>.md`, with one checkbox per step
   and any open question for the human written inside the step that needs it.
2. After approval, the SQL for the chosen type, as a candidate for review,
   naming the companion file it belongs in. Never executed.
3. The five NULL-safe invariant checks for Type 2 dimensions, as a view.
4. A diff summary against the hand-built reference when one is named.

# Instructions

1. **Plan first, then stop.** Write `plans/<dimension>_scd<type>.md` with
   checkbox steps in this order: read `AGENTS.md` hashing and window
   conventions; confirm the target columns from `DESCRIBE TABLE`; draft the
   statements; wrap in a transaction (Type 2 only); draft the invariant
   checks; diff against the named reference. Put every question as a note
   inside the step that raises it. Ask for approval and wait. Do not make
   critical decisions alone: the version boundary timestamp, the tracked
   attribute list, and the history type per attribute are human decisions.
2. **Execute one step at a time after approval**, marking each checkbox
   `[x]` as it completes. Re-read `AGENTS.md` if the session started
   elsewhere; a session started outside `chapters/chapter14` has no
   conventions loaded.
3. **Type 1:** one MERGE. `ON` the business key; `WHEN MATCHED AND` a guard
   built with `IS DISTINCT FROM` across every overwritten column; `WHEN NOT
   MATCHED THEN INSERT` every column including descriptive ones such as
   `merchant_name`. State that a re-run reports zero rows.
4. **Type 2 (batch extract):** two statements inside `BEGIN; ... COMMIT;`
   for a worksheet, or inside one Snowflake Scripting block (`BEGIN
   TRANSACTION;` ... `COMMIT;` with `EXCEPTION WHEN OTHER THEN ROLLBACK;
   RAISE;`) for anything scheduled, with the duplicate-key guard inside the
   block before `BEGIN TRANSACTION` and the two `SQLROWCOUNT` values in the
   `RETURN`, because the pair assumes one row per key per extract. First the close: `MERGE ... USING (SELECT business_key, extract_ts,
   SHA2(CONCAT_WS('|', NVL(col, ''), ...)) AS record_hash FROM staging) src
   ON tgt.business_key = src.business_key AND tgt.is_current = TRUE WHEN
   MATCHED AND tgt.record_hash <> src.record_hash THEN UPDATE SET
   tgt.effective_to = src.extract_ts, tgt.is_current = FALSE`. Then the
   insert: every staging row LEFT JOINed to the current versions where no
   current row exists, computing the same hash. The hash expression must be
   identical in both statements and match the recipe that built the
   dimension. For this fixture, extract_ts is explicitly assumed to be the
   business-effective change time. For another source, establish whether the
   boundary is effective time or observation time before generating the load.
   Late or retroactive changes need a correction policy; this pair assumes
   ordered batches and stable staging. Treat effective_from/effective_to as
   Type 2 metadata, not Type 0 business attributes.
5. **Type 3:** two statements, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS
   previous_<attr> <type>` and `ALTER TABLE ... ADD COLUMN IF NOT EXISTS
   <attr>_changed_at TIMESTAMP_NTZ`, then a MERGE whose `WHEN MATCHED AND`
   guard compares the attribute and whose UPDATE moves the current value into
   `previous_<attr>` before overwriting it. Say plainly that Type 3 keeps one
   prior value only and supports alternate classifications of the same
   facts. Use Type 2 for a sequence of event-time classifications.
6. **Invariant checks (always, for Type 2):** one current row per business
   key (`HAVING COUNT_IF(is_current) <> 1`, which fails on zero current rows
   as well as two; Snowflake's COUNT_IF returns 0 for a group with no match,
   so a COALESCE around it is only defensive), no overlapping windows (self-join on the business key
   with `a.<surrogate> < b.<surrogate>` and `a.effective_from <
   b.effective_to AND b.effective_from < a.effective_to`), no internal gap
   (`LAG(effective_to) OVER (PARTITION BY key ORDER BY effective_from)` earlier
   than the row's `effective_from`; facts before a key's first version are
   not a gap), no current row whose `effective_to IS DISTINCT FROM
   '9999-12-31'::TIMESTAMP_NTZ` (so a NULL end fails), and no window where
   either boundary is NULL or `effective_from >= effective_to`. Emit them as
   one `UNION ALL` view named `<dimension>_invariants` returning `check_name,
   failures`, so the manual check and a scheduled alert read one definition.
   These checks enforce structure. Also compare expected attribute values
   and fact attribution before and after the agreed change boundary.
7. **Diff, do not narrate.** When a reference file is named, list every
   difference between the candidate and the reference as a bullet per
   difference, with the reason. An empty list is a valid answer.
8. **Never run SQL against the account.** Never generate `DROP`, `TRUNCATE`,
   or `DELETE` against `gold_db.customers.dim_customers` or
   `gold_db.merchants.dim_merchants`.

# Worked Example

Prompt: `$scd-dimension Write a plan, as a markdown file with a checkbox per
step, for generating the batch close-and-insert pair for
gold_db.customers.dim_customers reading raw_db.crm.stg_customer_extract,
following AGENTS.md conventions, inside one explicit transaction, plus the
invariant validation queries. Put any question for me inside the plan. After
my approval, execute the plan one step at a time, marking each checkbox. Do
not run any SQL against the account.`

Expected plan (`plans/dim_customers_scd2.md`):

```
- [ ] 1. Read AGENTS.md: hash recipe, half-open windows, extract_ts boundary
- [ ] 2. Confirm columns: DESCRIBE TABLE gold_db.customers.dim_customers
- [ ] 3. Draft the close MERGE
         confirm: this fixture assumes extract_ts is the business-effective
         change time; another source needs its timestamp semantics reviewed
- [ ] 4. Draft the anti-join INSERT with the same hash expression
- [ ] 5. Wrap steps 3-4 in BEGIN; ... COMMIT;
- [ ] 6. Draft the five invariant checks as one view
- [ ] 7. Diff against chapter14_2_scd_patterns.sql section 3.3 and list differences
```

The reviewed output follows section 3.3 of `chapter14_2_scd_patterns.sql`.
Use the reference and the fixture assertions together: a matching diff does
not prove that another source has the same identity or timestamp semantics.
