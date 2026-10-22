# Chapter 14 CoCo Conventions

CoCo reads this file at the start of every session run from this directory.
It pins the modeling rules for the TechFlow gold layer. Decisions (grain,
history policy, format placement) are made by people; this file records them
so every prompt inherits them. Generation is the agent's job, execution is not.

## The model

- The star is the real gold layer, not a chapter-owned copy:
  `gold_db.transactions.fact_transactions` (one row per payment attempt, all
  statuses), `gold_db.transactions.fact_refunds` (one row per refund event,
  many per payment), `gold_db.customers.dim_customers` (SCD Type 2, one row
  per customer version), `gold_db.customers.dim_customers_current` (view, one
  row per customer), `gold_db.merchants.dim_merchants` (one row per merchant,
  conformed), `gold_db.calendar.dim_date` (one row per day, 2025-2027).
- State grain in every table `COMMENT`. Keep payment and refund event facts
  separate in this lab. A refund amount aggregated once per payment can fit
  payment grain if its as-of meaning and update policy are defined. Avoid
  multiplying payment amounts by joining directly to multiple refund rows.
- Captured revenue is `status IN ('COMPLETED', 'REFUNDED')`; refunds are
  subtracted from `fact_refunds`, never re-derived from a status. Finance owns
  the definition; the semantic view `gold_db.semantic.techflow_revenue`
  carries it.
- Keep merchant_category on dim_merchants for this fixture. Review a separate
  category dimension when it has its own attributes or shared hierarchy;
  wide dimensions are the lab choice, not a prohibition on parent tables.
- Surrogate keys serve versioning and multi-source integration: `customer_key`
  identifies one Type 2 version, which `customer_id` cannot. Name a surrogate
  `<entity>_key`; the lab uses `NUMBER AUTOINCREMENT`. A unique, stable,
  single-source natural key carries the join itself: `merchant_id` is the
  merchant join key and the RELY foreign key, and `transaction_id` is a
  degenerate dimension on the fact. If dim_merchants ever versions or gains a
  second source, add `merchant_key` and rebuild the foreign key on it. The
  date dimension uses its DATE key. The fact keeps `customer_id` and the
  customer_id/time-range join resolves the version at query time; a
  conventional dimensional fact loader resolves and stores the applicable
  surrogate version key for an equality join instead.
- Declared constraints carry `RELY` only after the duplicate, null, and orphan
  tests in `chapter14_1_star_schema.sql` return zero. Never propose `RELY` on
  `fact_transactions.customer_id`: `dim_customers` is Type 2 and the natural
  key repeats across versions.

## History policy (per attribute, not per table)

- `dim_customers`: address attributes (`address_line1`, `city`, `state`,
  `postal_code`) are Type 2; `customer_name` and `email` are Type 2;
  `effective_from` and `effective_to` are Type 2 control metadata. An original
  signup date would be Type 0 across all versions, but that attribute is not
  present in this fixture. Do not label the version start as Type 0.
- `dim_merchants`: `merchant_city` and `merchant_name` are Type 1;
  `merchant_category` is Type 3 during the electronics-to-retail transition
  (`previous_category`, `category_changed_at`), Type 1 otherwise. Type 3
  supports two alternate classifications of the same facts; it does not
  provide event-time history of every category change.
- `dim_date`: Type 0, rebuilt rarely.

## SCD implementation conventions

- Change detection uses `record_hash = SHA2(CONCAT_WS('|', NVL(col, ''), ...))`
  over the tracked attributes, in the column order of the table. Every column
  is NVL-wrapped; a bare NULL inside `CONCAT_WS` hides changes. The pipe is
  the delimiter Chapter 5 chose; a value containing `|` can collide with a
  shifted neighbor, so flag any tracked attribute that may carry one.
- Validity windows are half-open: `effective_from` inclusive, `effective_to`
  exclusive, `'9999-12-31'::TIMESTAMP_NTZ` marks the current version, all
  timestamps `TIMESTAMP_NTZ` in UTC.
- Type 2 from a batch extract is two statements in one explicit transaction:
  close first (MERGE ... WHEN MATCHED AND hash differs THEN UPDATE), then
  insert every extract row with no current version (anti-join on
  `is_current = TRUE`). Never a single MERGE that tries to update and insert
  on the same key. This fixture assumes `extract_ts` is also the
  business-effective change time; use it as the version boundary. For another
  feed, establish whether timestamps describe effective time or observation
  time. Late or retroactive changes require a separate correction policy;
  do not silently substitute load time for business-effective time.
- Batch contract for that pair: one row per business key per extract,
  extracts applied in order, staging unchanged while the pair runs. Guard the
  extract for duplicate keys before the transaction opens (a Scripting block that raises), never inside the MERGE.
- The reusable form is one Snowflake Scripting block: the duplicate-key
  guard, then `BEGIN TRANSACTION;` close; insert; `COMMIT;` with `EXCEPTION
  WHEN OTHER THEN ROLLBACK; RAISE;`, returning the two `SQLROWCOUNT` values.
  A failed statement inside an explicit transaction is rolled back on its own
  while the transaction stays open, so a worksheet run that fails between the
  close and the insert needs an explicit `ROLLBACK` before anything else;
  DDL commits implicitly.
- Type 2 from a stream is the Chapter 5 stable-delta pattern (temp table,
  UPDATE, INSERT, one transaction). Pick the shape by the source, never mix.
- Type 1 is a single MERGE with `IS DISTINCT FROM` change detection in the
  `WHEN MATCHED` guard, so a replayed extract updates nothing.
- Type 3 adds `previous_<attribute>` and `<attribute>_changed_at` columns with
  `ADD COLUMN IF NOT EXISTS` (one statement per column) and updates them in
  the same MERGE that moves the current value.
- Every generated SCD change ships with the five invariant checks, NULL-safe:
  one current row per business key (`COUNT_IF(is_current) <> 1` fails on zero
  current rows as well as two; Snowflake's COUNT_IF returns 0 for a group with
  no match, so the COALESCE in the reference view is only defensive), no
  overlapping windows, no internal gap
  between consecutive windows (`LAG(effective_to)` over the key ordered by
  `effective_from`, failing where it is earlier than the next
  `effective_from`; facts before a key's first version are a data question,
  not a gap), no current row whose end is not the sentinel (`IS DISTINCT
  FROM`, so a NULL end fails), and no window with a NULL boundary or
  `effective_from >= effective_to`. The reference is the
  `dim_customers_invariants` view in `chapter14_4_coco.sql`; emit checks as a
  view so the manual run and any scheduled check read one definition. These
  are structural checks for this lab. Also verify the tracked attributes and
  payment attribution around the agreed change boundary; passing the view
  does not establish business correctness.
- The hash recipe is the change-detection contract: fixed column order, NVL
  wrapping, one delimiter. Never propose `TO_JSON(OBJECT_CONSTRUCT(...))` as
  the hashed string; Snowflake documents its key order as unpredictable.

## Optional Data Vault and table formats

- Data Vault is an optional integration pattern, not a requirement triggered
  by a source count. Compare source-history and audit needs, change handling,
  automation, and team capacity with loading conformed dimensions directly.
- Hash keys assume one business-key domain per fixture hub. Case-folding is
  valid because fixture identifiers are case-insensitive. When source domains
  overlap without shared identity, use an agreed discriminator or identity
  mapping. Equal text or hashes do not resolve cross-source identity.
- The customer satellite uses load_ts for source-effective time only as a
  teaching simplification. A full audit model retains effective and arrival
  timestamps separately. Hubs and the merchant satellite use arrival time.
- All lab objects use native tables. Assess other formats from actual
  consumers, file-level access, write ownership, supported operations, and
  maintenance costs. Calendars, dimensions, and marts can also have external
  consumers.

## Working rules

- Plan first. Before generating anything, write the plan to
  `plans/<task>.md` with one checkbox per step, put any question for the
  human inside the plan, stop, and wait for approval. Then execute one step at
  a time, marking each checkbox as it completes.
- Generate candidates only. Never run DDL or DML against the account. Output
  the full statement for human review and name the file it belongs in.
- Reverse-engineer before proposing. On an existing estate, describe what is
  there (grain sentences, facts-against-dimensions map) and wait for
  corrections before proposing a target design.
- Every generated table or column comment states the business meaning and,
  for tables, the grain. Payments-finance vocabulary, not schema vocabulary.
- Never generate `DROP SCHEMA ... CASCADE` against `gold_db.transactions`,
  `gold_db.customers`, or `gold_db.merchants`: all three are shared with
  earlier chapters. Chapter-owned objects: `gold_db.calendar`, `raw_db.partners`,
  `vault_db`.

## Fixture facts

- Chapter 12 rows in `fact_transactions` carry a `TXN-CH12-` prefix; Chapter 12
  rows in `dim_customers` carry `record_hash` of `CH12-SEED` or
  `CH12-BACKFILL`. Chapter 14 rows carry ids `CUST-CH14-*`, `MERCH-CH14-*`,
  and `effective_from = '2026-03-01 06:00:00'` for the two moved customers.
- The seeded window is 2025-01-01 to 2026-07-01. Bound time-based examples to
  it explicitly rather than to `CURRENT_DATE`.
- Categories in the fixture: retail, travel, dining, software, streaming,
  gaming, groceries, fitness, and electronics (the Chapter 5 merchants
  MERCH_ELEC_1 and MERCH_ELEC_2, or the chapter-owned MERCH-CH14-ELEC01 and
  MERCH-CH14-ELEC02 that the setup adds when the dimension has none). Category
  tests compare case-insensitively: Chapter 5 writes ELECTRONICS, Chapter 12
  lower-cases it.
- The vault loaders read the simulated source extracts
  `raw_db.crm.customer_history` and `raw_db.partners.merchant_directory`,
  staged by the Data Vault script from the gold layer. Never propose a vault
  loader that reads `dim_customers` or `dim_merchants` as its source.
