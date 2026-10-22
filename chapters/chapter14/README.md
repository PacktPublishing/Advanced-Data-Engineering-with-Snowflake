# How To Run Chapter 14 (Data Modeling in Snowflake using AI-Assisted Practices)

This chapter completes the TechFlow star schema on the gold layer the book already built, implements SCD Types 1, 2, and 3 with MERGE-based patterns, shows a Data Vault on the side, and hands the mechanical modeling work to CoCo. Everything is in-database SQL plus one CoCo session; the AI parts run from this directory so `AGENTS.md` and the `scd-dimension` skill load.

The chapter ships setup, section scripts, and teardown. Follow their prerequisites and optional-block instructions, then run each section's validation set. The opening modeling discussion and section 5's table-format guidance have no separate scripts.

| File | Chapter section | Needs |
|------|-----------------|-------|
| [chapter14_0_setup.sql](chapter14_0_setup.sql) | Fixtures for every section, prerequisite guard (one named error per missing object), reversibility snapshot, the electronics pair when the dimension has none — **run once first** | Chapter 5 + Chapter 12 gold layer (rerun `chapter12_0_setup.sql` if you tore Chapter 12 down after Chapter 13) |
| [chapter14_1_star_schema.sql](chapter14_1_star_schema.sql) | Building and optimizing the TechFlow star schema (section 2) — **run once**; teardown before a rerun | OWNERSHIP of `fact_transactions` and `dim_merchants` for the ALTERs |
| [chapter14_2_scd_patterns.sql](chapter14_2_scd_patterns.sql) | Managing dimension history with SCD Types 1, 2, and 3 (section 3) | Setup only; OWNERSHIP of `dim_merchants` for the Type 3 ALTER |
| [chapter14_3_data_vault.sql](chapter14_3_data_vault.sql) | Introducing Data Vault for complex enterprises (section 4) — **optional**; stages the two simulated source extracts (`raw_db.crm.customer_history`, `raw_db.partners.merchant_directory`) the loaders read | `CREATE DATABASE` (creates `vault_db`), `CREATE TABLE` on `raw_db.crm` and `raw_db.partners` |
| [chapter14_4_coco.sql](chapter14_4_coco.sql) | Accelerating modeling work with Snowflake CoCo (section 6) — reviewed session outcome: grain comments, the invariants view, the manual check | Setup + section 3; OWNERSHIP of the four commented tables, `CREATE VIEW` on `gold_db.customers` |
| [chapter14_teardown.sql](chapter14_teardown.sql) | Reverses every change, including the two shared dimensions | Any edition |
| [AGENTS.md](AGENTS.md) | 6.1 CoCo modeling conventions for this directory | — |
| [.cortex/skills/scd-dimension/SKILL.md](.cortex/skills/scd-dimension/SKILL.md) | 6.2 The plan-first SCD skill the chapter invokes with `$scd-dimension` | CoCo (Chapter 6) |
| [chapter14_static_checks.py](chapter14_static_checks.py) | Offline consistency checks, including manuscript snippet alignment and the Packt heading and file-name rules — run before committing | Python 3.9+ |
| [chapter14_logic_sim.py](chapter14_logic_sim.py) | Runs the real statements against a DuckDB emulation of the Chapter 5 + 12 gold layer: expected counts, idempotent reruns, invariant counterexamples, byte-identical teardown | Python 3.9+, `pip install duckdb sqlglot` |

Run order: `0_setup` → `1_star_schema` → `2_scd_patterns` → (`3_data_vault`) → `4_coco` → `teardown`. Sections 2, 3, and 4 are independent of each other; section 6 reads the dimension state section 3 leaves behind but its checks also pass on an untouched dimension. The constraint block in section 2 runs once (a second `ADD CONSTRAINT` of the same name fails), and the setup guard refuses to run again after section 3 until the teardown has restored the dimension, so the loop for a second pass is `teardown` → `0_setup` → sections.

## Prerequisites

- **Chapter 5 and Chapter 12 completed.** The chapter models the gold layer the book already has: `gold_db.transactions.fact_transactions` and the SCD Type 2 `gold_db.customers.dim_customers` from Chapter 5, plus `gold_db.merchants.dim_merchants`, `gold_db.transactions.fact_refunds`, `gold_db.customers.dim_customers_current`, and the 50,000-row top-up from [chapter12_0_setup.sql](../chapter12/chapter12_0_setup.sql). The setup guard raises one named error (-20014 to -20019) per missing object, each saying which script supplies it. Chapter 12 tells its readers to run its teardown after Chapter 13; that removes these objects, so run `chapter12_0_setup.sql` again before this chapter if you did.
- **Chapter 6 completed** for section 6: CoCo installed and authenticated.
- Role **`SYSADMIN`**, or any role holding the privileges below. If an earlier chapter created `gold_db` or `raw_db` as `ACCOUNTADMIN`, grant `SYSADMIN` ownership of the four shared tables and of `raw_db.crm` first.
  - Every file: `USAGE` on `BOOK_WH`, `USAGE` on `gold_db` and `raw_db` and their schemas, `SELECT` on the shared gold tables and the `dim_customers_current` view.
  - Setup: `CREATE SCHEMA` on `raw_db`, `CREATE TABLE` on `raw_db.crm` and `raw_db.partners`.
  - Section 2: `CREATE SCHEMA` on `gold_db`, `CREATE TABLE` on `gold_db.calendar`, `CREATE VIEW` on `gold_db.transactions`, `OWNERSHIP` of `fact_transactions` and `dim_merchants` (constraints are `ALTER TABLE`).
  - Section 3: `INSERT` and `UPDATE` on `dim_customers` and `dim_merchants`, `OWNERSHIP` of `dim_merchants` (Type 3 `ADD COLUMN`).
  - Section 4 (optional): `CREATE DATABASE`, `CREATE TABLE` on `raw_db.crm` and `raw_db.partners` for the two source extracts.
  - Section 6: `OWNERSHIP` of `fact_transactions`, `fact_refunds`, `dim_customers`, and `dim_merchants` (`COMMENT ON` is an `ALTER`), `CREATE VIEW` on `gold_db.customers`.
  - Teardown: everything above plus `DELETE` on `dim_customers` and `dim_merchants`, and `DROP` rights on the chapter-owned objects.
- Any Snowflake edition. No preview features.

## Expected counts (stock Chapter 5 + Chapter 12 fixtures, first run)

| Where | Statement | Expect |
|---|---|---|
| Setup guard | prerequisite block | `Prerequisites present: 50024 payments, about 2250 refunds, 47 merchants, 500 seeded current customers, both movers current, current view present.` (an `Object ... does not exist or not authorized` error names the missing or unreadable table; errors -20014 to -20019 each name one missing prerequisite and the script that supplies it) |
| Setup | electronics pair insert | inserted 0 with the stock fixture, 2 on a dimension with no electronics merchant |
| Setup | fixture check | 4, 3, 2, 2 rows |
| 2.1 | `dim_date` span | 1,095 days, 2025-01-01 to 2027-12-31 |
| 2.2 | guard block with the four `ALTER TABLE` statements inside it | `Every key test returned zero. Four constraints now carry RELY.` |
| 2.2 | `TABLE_CONSTRAINTS` after the declarations | four rows, `rely = YES` (the column holds `YES`/`NO`; `SHOW PRIMARY KEYS` does not report RELY at all) |
| 2.3 | star row count (`star_transactions_rows`, `fact_transactions_rows`) | equals `fact_transactions` (50,024) |
| 2.3 | `EXPLAIN` on a channel aggregate | `DIM_MERCHANTS` absent from the plan, `DIM_DATE` present |
| 3.2 | Type 1 MERGE | inserted 1, updated 3; re-run 0 / 0 |
| 3.3 | rollback demonstration block | `Rolled back after closing 2 versions. Error was: Division by zero`, then `movers_still_current = 2` |
| 3.3 | executable Type 2 block (guard, close, insert, commit) | `Type 2 pair committed: closed 2, inserted 3.`; rerun: `closed 0, inserted 0` |
| 3.3 | worksheet pair block (comment; the chapter's form) | updated 2 after the MERGE, inserted 3 after the INSERT |
| 3.4 | point-in-time versus current-slice totals | equal to the cent; an `unknown` row for the Chapter 5 payments that precede their customers' first version |
| 3.5 | Type 3 MERGE | updated 2 (`MERCH_ELEC_1` and `MERCH_ELEC_2`, or `MERCH-CH14-ELEC01` and `MERCH-CH14-ELEC02` when the setup had to add them) |
| 4 | vault validation set | four TRUE |
| 6 | invariant checks | five rows, all zero |

## Reversibility contract

Section 3 writes into two tables earlier chapters own. Every write is fixed and reversible:

| Table | What changes | Reversed by |
|---|---|---|
| `gold_db.merchants.dim_merchants` | 3 rows corrected, 1 row added (`MERCH-CH14-NEW01`), 2 rows reclassified, 2 columns added, table comment set; on a dimension with no electronics merchant, 2 rows added (`MERCH-CH14-ELEC01`, `MERCH-CH14-ELEC02`) | `DELETE` of every `MERCH-CH14-` id, restore of the fixture ids from `raw_db.partners.dim_merchants_before_ch14` (snapshot taken by setup before any change), `DROP COLUMN IF EXISTS`, `UNSET COMMENT` |
| `gold_db.customers.dim_customers` | 2 seeded versions closed, 3 versions inserted (`effective_from = 2026-03-01 06:00:00`, ids `CUST-CH12-0007`, `CUST-CH12-0042`, `CUST-CH14-0001`), table and column comments set | targeted `DELETE`, then reopen the two `CH12-SEED` versions, `UNSET COMMENT` |
| `gold_db.transactions.fact_transactions`, `fact_refunds` | `pk_fact_transactions` gains `RELY`; `fk_txn_merchant` added; table comments set | `MODIFY CONSTRAINT ... NORELY`, `DROP CONSTRAINT` guarded by a `TABLE_CONSTRAINTS` lookup, `UNSET COMMENT` |

Run `chapter14_teardown.sql` before returning to Chapter 12's examples, whose category totals change after the Type 1 correction (that restatement is the point of the section 3.2 warning).

## Modeling choices and limits

Surrogate keys serve versioning and multi-source integration: customer_key identifies one Type 2 version, which customer_id cannot. A unique, stable, single-source natural key carries the join itself, so merchant_id is the merchant join key and the RELY foreign key; if dim_merchants ever versions or gains a second source, add merchant_key and rebuild the foreign key on it. The fact keeps customer_id and the customer_id/time-range join resolves a historical version at query time; a conventional fact load stores the applicable customer_key instead. The date dimension uses its DATE key. Keeping merchant_category in dim_merchants serves the fixture's requirements; a separate category dimension may serve shared attributes or hierarchies elsewhere.

A payment-level refund aggregate can fit payment grain with a defined as-of meaning and update policy. The lab retains separate payment and refund event facts. Joining payments to multiple raw refunds and summing payment amounts would multiply those amounts. Type 3 reports the same facts under two retained classifications; it does not provide general event-time category history. Type 0 means retaining an original business attribute, such as signup date. The fixture has no such customer column; effective_from/effective_to are Type 2 control metadata.

Data Vault remains optional. Assess audit and source-history requirements, integration changes, automation, and team ownership instead of using a source-count threshold. The hash recipe assumes one case-insensitive identifier domain per hub. Independent source domains need an agreed discriminator or identity mapping. The customer satellite uses load_ts as source-effective time for illustration; a full audit model retains arrival time separately. All examples use native tables. External consumers may need calendars, dimensions, or marts as well as facts; assess access requirements before choosing another format.

## Why the fixtures look the way they do

- **The customer extract is a delta, not a full snapshot.** The Chapter 12 seed stores the literal tag `CH12-SEED` in `record_hash` (so its teardown can find the rows), not a real hash. A full snapshot compared by hash would make every seeded customer look changed. The delta is sufficient to demonstrate changed and new customers.
- **Movers go to Florida** because the Chapter 12 seed never assigns `FL`, so the change is guaranteed whatever the hashed current state is. The fixture assumes the extract timestamp `2026-03-01` is also the business-effective time of each move, giving the range join payments on both sides. If extract_ts instead records extraction time, the windows describe when changes were observed. Late or retroactive changes need a separate effective timestamp and correction policy.
- **The Type 3 fixture uses the two Chapter 5 electronics merchants** (`MERCH_ELEC_1`, `MERCH_ELEC_2`); the Chapter 12 cohort's eight categories never include electronics, so the Type 1 corrections (which touch only `MERCH-CH12-` merchants) cannot collide with the reclassification. Chapter 5 writes `ELECTRONICS` into the fact and Chapter 12 lower-cases it when it builds `dim_merchants`, so every category test is case-insensitive. A dimension with no electronics merchant at all (the technical reviewer's account) gets the chapter-owned pair `MERCH-CH14-ELEC01` and `MERCH-CH14-ELEC02` from the setup, so the MERGE reports 2 either way.
- **The vault loads from simulated source extracts, not from the mart.** The Data Vault script stages `raw_db.crm.customer_history` (every customer version, as a CRM that keeps its own history would export it) and `raw_db.partners.merchant_directory` (current merchant attributes) from the gold layer, and the hub and satellite loaders read only those. Payments have no separate raw table in the account, so the link loader reads `fact_transactions`.
- **Both merchant fixtures derive from the pristine snapshot**, never from the live table, so re-running the setup before section 3 rebuilds identical fixtures. After section 3 the guard asks for the teardown first, because every quoted count assumes a fresh dimension.
- **The Type 2 pair has a batch contract**: one row per customer per extract, extracts applied in order, from a staging table that does not change while the pair runs. The duplicate-key guard enforces the first half; the second and third are the loader's job. The hash recipe pipe-delimits NVL-wrapped values in a fixed column order, so a value containing `|` can collide with a shifted neighbor; the seeded data has none. A recipe that must survive such values keeps the fixed order and the NVL wrapping and either escapes the delimiter in every column (`REPLACE(col, '|', '\\|')`) or prefixes each value with its length. Do not swap in `TO_JSON(OBJECT_CONSTRUCT(...))`: Snowflake documents the key order of that string as unpredictable, so equal rows can hash differently. Changing the recipe means rehashing the whole dimension in one migration, since the close MERGE compares stored and computed hashes.

## Offline checks

`python3 chapter14_static_checks.py --manuscript /path/to/Chapter_14_*.md` verifies the file inventory, balanced parentheses, banned patterns (no `CASCADE` on shared schemas, no stray `<REPLACE>` on standardized objects), teardown coverage of every fixture id, the manuscript's heading rules (sentence case, unnumbered `##`, `N.M` on `###`), that no companion file name leaks into the prose, and that every SQL block in the manuscript appears verbatim (whitespace-normalized) in one of these scripts.

`python3 chapter14_logic_sim.py` (needs `duckdb` and `sqlglot`) builds an emulation of the Chapter 5 + 12 gold layer scaled to 5,024 payments and runs the relational statements from this directory through it: every quoted count at that scale, the rerun-reports-zero property of every loader, the conditions the Snowflake Scripting guards test (re-evaluated in Python, since the blocks themselves are skipped), the Type 2 pair extracted from its Scripting block plus a rollback emulation, the invariants view against four counterexamples (zero current versions, NULL end date, reversed window, internal gap), the hub loader and the vault validation set with a case-and-whitespace variant of an existing key present in the CRM extract, the RELY validation query against an emulated `TABLE_CONSTRAINTS` holding the documented `YES` literal, a teardown after which both shared dimensions compare equal to the baseline on every column, and a second pass on a dimension with no electronics merchant, which must get the chapter-owned pair, reclassify it, and tear it down cleanly. It does not exercise Snowflake itself: RELY and join elimination, EXPLAIN, COMMENT and UNSET COMMENT, and the Scripting exception paths are listed as skipped and are verified only by a live run.

The invariant view validates the lab's interval and current-row contract. Attribute-value and payment-attribution assertions provide separate evidence about its business behavior. A matching reference diff and clean intervals do not establish that another source has the same business meaning.

## Live run status

Static checks and DuckDB emulation cover fixture counts, guard conditions, and teardown at reduced scale. Snowflake Scripting exception paths, `RELY` declarations, `TABLE_CONSTRAINTS`, and `EXPLAIN` output still need a live run. First live run: `snow sql -c book -f chapter14_0_setup.sql`, then each section file, recording any drift in the counts table above. Run the files with a client that stops on the first error (Snowsight, `snow sql`); SnowSQL continues by default, which the Scripting blocks are designed to survive but the worksheet forms are not.
