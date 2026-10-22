# How To Run Chapter 5 (Advanced SQL Transformations)

This chapter is pure in-database SQL — no Kafka, no OpenFlow, no external integrations. Every script runs against a single Snowflake account as long as `RAW_DB`, `SILVER_DB`, and `BOOK_WH` from Chapter 4 already exist.

The chapter ships **one script per main section**, each embedding the sample data it needs so a section runs standalone from top to bottom (TR feedback, 2026-08 — no hopping between a scripts file and a test-data file):

| File | Chapter section | Needs |
|------|-----------------|-------|
| [chapter5_0_setup.sql](chapter5_0_setup.sql) | Shared database/schema bootstrap — **run once first** | Any edition |
| [chapter5_1_window_functions.sql](chapter5_1_window_functions.sql) | 1. Applying Window Functions for Analytics and Fraud Detection | Any edition |
| [chapter5_2_recursive_ctes.sql](chapter5_2_recursive_ctes.sql) | 2. Navigating Hierarchical Data with Recursive CTEs | Any edition |
| [chapter5_3_incremental_patterns.sql](chapter5_3_incremental_patterns.sql) | 3. Building Incremental Transformation Patterns | Any edition |
| [chapter5_4_query_performance.sql](chapter5_4_query_performance.sql) | 4. Optimizing Query Performance | **Enterprise+** (both ALTERs) |
| [chapter5_5_variant_data.sql](chapter5_5_variant_data.sql) | 5. Transforming Semi-Structured VARIANT Data | Any edition |

Dependencies between section files: `chapter5_4` reads the `fact_transactions` table that `chapter5_1` creates and seeds. Everything else is independent once `chapter5_0_setup.sql` has run.

## Prerequisites

- **Chapters 2–4 completed** so `SILVER_DB`, `BOOK_WH`, and the streaming demo objects are in place.
- Role **`ACCOUNTADMIN`** (or equivalent with `CREATE DATABASE`, `CREATE SCHEMA`, `CREATE TABLE`, `CREATE STREAM`, and `ALTER TABLE` on the targets).
- Edition **Enterprise or higher** for the clustering key (Section 4.2) and search optimization (Section 4.3) steps. Trial accounts will error on those two ALTERs — skip them or upgrade.

## Database / schema layout bootstrapped by chapter5_0_setup.sql

| Database | Schema | Purpose |
|----------|--------|---------|
| `gold_db` | `transactions` | `fact_transactions` (Sections 1 and 4) |
| `gold_db` | `reference` | `dim_diagnosis_codes` (Section 2.1–2.3) |
| `gold_db` | `claims` | `fact_claims` (Section 2.3) |
| `gold_db` | `customers` | `dim_customers`, `dim_customer_360` (Section 3) |
| `raw_db` | `crm` | CRM customer table + stream (Section 3.1) — **new in Chapter 5** |
| `raw_db` | `billing` | Billing customer table + stream (Section 3.2) — **new in Chapter 5** |
| `raw_db` | `streaming` | VARIANT/XML landing tables (created in chapter5_5); schema usually exists from Chapter 4 |
| `silver_db` | `reference` | `bill_of_materials` (Section 2.4 BOM graph) |

Both `raw_db` and `silver_db` databases themselves were created in Chapter 4 — the setup script adds `gold_db` plus the schemas listed above. Tables live in the section files that use them.

## Step-by-step

1. Open [chapter5_0_setup.sql](chapter5_0_setup.sql) in a Snowsight worksheet and run it once.
2. Open the section file you are reading and run it **top to bottom**: DDL first, then its embedded sample data, then the analytic queries in chapter order. Expected results are in comments above each query.
3. For Section 3.1 SCD Type 2, follow the staged stream-draining order in the comment block at the end of 3.1 ([details below](#scd-type-2-observation-flow)). A single run of the stable-delta block will not expose the close-then-insert behaviour by itself.
4. Run [chapter5_4_query_performance.sql](chapter5_4_query_performance.sql) only on Enterprise Edition+, after chapter5_1 has created and seeded `fact_transactions`.

## Test data (embedded per file)

Expected row counts after running each file's seed:

| Table | Rows | Seeded by |
|-------|-----:|-----------|
| `gold_db.transactions.fact_transactions` | 19 | chapter5_1 |
| `gold_db.reference.dim_diagnosis_codes` | 7 | chapter5_2 |
| `gold_db.claims.fact_claims` | 6 | chapter5_2 |
| `silver_db.reference.bill_of_materials` | 7 | chapter5_2 |
| `raw_db.crm.customer` | 3 | chapter5_3 |
| `raw_db.billing.customer` | 2 | chapter5_3 |
| `raw_db.streaming.raw_transactions` | 3 | chapter5_5 |
| `raw_db.streaming.raw_orders` | 2 | chapter5_5 |
| `raw_db.streaming.raw_fhir_patients` | 3 | chapter5_5 |
| `raw_db.streaming.raw_fhir_claims` | 2 | chapter5_5 |

The seed is designed to make each analytic query produce a distinctive, easy-to-verify result:

- `CUST_FRAUD` fires 6 transactions in the last 20 minutes — triggers the MEDIUM/HIGH velocity buckets in Section 1.2.
- `MERCH_GROC_1..3`, `MERCH_ELEC_1..2`, `MERCH_TRVL_1` give each category enough merchants to show a real `DENSE_RANK()` ordering in Section 1.3.
- `MERCH_GAP` has activity at hours `-10..-8` and then silence until hour `-3` — the Section 1.4 gap query picks this up as `hours_since_last > 2`.
- The ICD-10 tree has both an in-category billable path (`I00-I99 > I20-I25 > I25 > I25.1 > I25.10`) and an unrelated respiratory sibling (`J00-J99`) so the Section 2.3 recursive descendants correctly include the five circulatory claims and exclude the respiratory one.
- `raw_db.streaming.raw_transactions` intentionally seeds `TXN-1002` with `"amount": "N/A"` — a dirty record. This motivates Section 5.3's `TRY_CAST` defense.

## Expected results (quick checks)

### Section 1.2 — Velocity

Expect 4 rows, all `CUST_FRAUD`, transitioning from `MEDIUM` to `HIGH` as the 5-minute window fills up:

```
T0003 CUST_FRAUD MERCH_ELEC_1 420.00 ... txn_count_5min=3 velocity_risk=MEDIUM
T0004 CUST_FRAUD MERCH_ELEC_1 180.00 ... txn_count_5min=4 velocity_risk=MEDIUM
T0005 CUST_FRAUD MERCH_TRVL_1 900.00 ... txn_count_5min=5 velocity_risk=HIGH
T0006 CUST_FRAUD MERCH_TRVL_1 150.00 ... txn_count_5min=6 velocity_risk=HIGH
```

### Section 1.3 — Merchant ranking

Seven rows — one per (category, month, merchant). `MERCH_ELEC_1` and `MERCH_TRVL_1` both land at `category_rank = 1` in their respective categories, and `revenue_share` across each category sums to 1.0.

### Section 1.4 — Gaps

`MERCH_GAP` shows `hours_since_last = 5` (the designed gap from hour -8 to hour -3). Other merchants that only appear at a single hour show no output because they have no prior hour to compare against. Note the 2026-08 revision: `LAG()` is evaluated once in the `with_prev` CTE and `DATEDIFF` derives from it (Snowflake has no named-window clause, so this is the way to avoid repeating the window spec).

### Section 2.2 — Recursive upward

Single row with `depth = 5` and `full_path` starting at `I00-I99` and ending at `I25.10`.

### Section 2.3 — Recursive downward

One row: `category='I00-I99', claim_count=5, total_amount=17500.00`. Excludes `CLM999` (respiratory) — recursion walked only the circulatory subtree. The depth-guarded variant (`lvl < 7`) returns the same descendant set on this healthy seed.

### Section 5.1 — VARIANT extraction

The chapter listing casts `raw_data:amount` directly to number; the seeded row TXN-1002 (`"amount": "N/A"`) **raises** `Failed to cast variant value N/A to FIXED...` — that motivates Section 5.3. The runnable SELECT in chapter5_5 filters bad amounts.

### Section 5.2 — FLATTEN

3 rows from the single FLATTEN on `raw_transactions.line_items`, and 6 rows from the chained FLATTEN on `raw_orders.shipments → items`.

### Section 5.3 — TRY_CAST

3 rows. `TXN-1002` reports `amount_status = PARSE_ERROR`; the others `OK`.

## SCD Type 2 observation flow

Section 3.1's two-row Type 2 behaviour (close old, insert new) depends on **draining the stream in stages**. Run the stable-delta `BEGIN` … `COMMIT` block once per stage; if you combine steps without advancing the stream, Snowflake can collapse net changes.

Correct order:

1. Run the Section 3.1 transaction block once → inserts 3 rows in `gold_db.customers.dim_customers`, all `is_current = TRUE`.
2. `UPDATE raw_db.crm.customer SET email = 'alice.new@example.com', updated_at = CURRENT_TIMESTAMP() WHERE customer_id = 'C1001';`
3. Run the transaction block again → closes the old `C1001` row (`is_current = FALSE`, `effective_to` populated).
4. Run the transaction block a third time → inserts the new `C1001` version. `SELECT` now returns two rows for `C1001`.

## Troubleshooting

- **`SQL compilation error: Function TRY_CAST cannot be used with arguments of types VARIANT and NUMBER(12,2)`** — you called `TRY_CAST` directly on a VARIANT extraction. Snowflake requires casting the VARIANT to STRING first: `TRY_CAST(raw_data:amount::STRING AS NUMBER(12,2))`. Alternative: `TRY_TO_NUMBER(raw_data:amount::STRING, 12, 2)`. Section 5.3 of the chapter and the repo script both use the correct form.
- **`Failed to cast variant value N/A to FIXED[SB8](12,2)`** on Section 5.1 — expected on the dirty seed. Filter the row out or switch to the TRY_CAST form.
- **`Unsupported feature 'SEARCH OPTIMIZATION'`** — Trial / Standard edition. Upgrade or skip Section 4.3.
- **`Clustering is not supported for tables less than a certain size`** warning — harmless; `SYSTEM$CLUSTERING_INFORMATION` still returns stats.
- **Empty result from Section 3.1 MERGE** — the stream has already been consumed. Re-seed bronze customers, or simplest: `DROP STREAM` / `CREATE STREAM` plus re-running the seed.
- **`Schema 'RAW_DB.CRM' does not exist`** (or `RAW_DB.BILLING`, or any of the `silver_db.*` schemas) — you skipped chapter5_0_setup.sql. Run it first.
