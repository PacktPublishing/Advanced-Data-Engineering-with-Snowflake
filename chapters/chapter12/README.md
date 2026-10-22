# How To Run Chapter 12 (Semantic Layer and Semantic Views)

This chapter is pure in-database SQL plus two UI walkthroughs (Cortex Agents
in Snowsight, and a CoCo session). Everything runs against a single Snowflake
account.

The chapter ships **one script per main section**, each runnable top to bottom
once `chapter12_0_setup.sql` has run, and each embedding the data and the
validation it needs so a section runs standalone.

| File | Chapter section | Needs |
|------|-----------------|-------|
| [chapter12_0_setup.sql](chapter12_0_setup.sql) | 2.2 Preparing the TechFlow Gold Layer — **run once first** | Any edition; Chapter 5 data for meaningful output |
| [chapter12_1_semantic_layer.sql](chapter12_1_semantic_layer.sql) | 1. Bridging Technical Schemas and Business Meaning with the Semantic Layer | Any edition |
| [chapter12_2_create_view.sql](chapter12_2_create_view.sql) | 2.3 Creating the Semantic View, 2.4 Extending the View, 2.5 Inspecting the View and Choosing a Deployment Verb | Any edition |
| [chapter12_3_query_view.sql](chapter12_3_query_view.sql) | 3. Querying Semantic Views Using SQL and Natural Language | Any edition for SQL |
| [chapter12_3_query_view.sql, agent block](chapter12_3_query_view.sql) | 3.3 Asking the First Natural Language Question | Cortex Agents in the region or cross-region inference; CREATE AGENT and SNOWFLAKE.CORTEX_USER |
| [chapter12_4_agent_backing.sql](chapter12_4_agent_backing.sql) | 4. Backing Cortex Agents with Semantic Views and the YAML Specification | Cortex-enabled region or cross-region inference |
| [chapter12_5_coco.sql](chapter12_5_coco.sql) | 5.1 Extending the Model with the semantic-view Skill, 5.2 Reviewing the Candidate Before Executing | CoCo installed and authenticated (Chapter 6) |
| [chapter12_teardown.sql](chapter12_teardown.sql) | Reverses the setup: deletes the tagged rows, drops the chapter objects and its two schemas with RESTRICT. Run before returning to an earlier chapter, and after Chapter 13 if you continue there | Any edition |
| [techflow_revenue.yaml](techflow_revenue.yaml) | 4.3 Round-Tripping the YAML Specification | Regenerate from a live export |
| [AGENTS.md](AGENTS.md) | 5. CoCo session conventions for this directory | — |
| [chapter12_static_checks.py](chapter12_static_checks.py) | Offline consistency checks — run before committing | Python 3.9+ |

Run order: `0_setup` → `1_semantic_layer` → `2_create_view` → `3_query_view` →
`4_agent_backing` → `5_coco` → `teardown`. Sections 1 and 3 onward each
depend only on the setup and, from section 3, on the view existing. The section 4 agent Preview retest also
requires the agent created in section 3.3.

## Prerequisites

- **Chapter 5 completed.** The semantic view sits on the real gold layer:
  `gold_db.transactions.fact_transactions` and
  `gold_db.customers.dim_customers`. The setup script guards the database and
  schemas with `IF NOT EXISTS` so it will not error on a fresh account, but the
  labs only produce meaningful output on top of Chapter 5 data.
- **Chapter 6 completed** for section 5: CoCo installed and authenticated.
- Role **`SYSADMIN`**, or any role with `USAGE` and `CREATE SCHEMA` on
  `gold_db`, `CREATE TABLE` / `CREATE VIEW` on the target schemas, `SELECT`,
  `INSERT`, and `DELETE` on the two shared Chapter 5 tables,
  `CREATE SEMANTIC VIEW` and `CREATE AGENT` on `gold_db.semantic`, the
  `SNOWFLAKE.CORTEX_USER` database role, and `USAGE` on `BOOK_WH`. For agent
  calls, these grants must be held by the user's default role; set its default
  warehouse to `BOOK_WH`. Table 12.2 consumer templates are in the query script.
- Any Snowflake edition. The semantic view object carries no separate license.
  Cortex Agents and CoCo bill under their own consumption models, and the SQL
  they generate runs on billable warehouse compute.

## The model: four logical tables, three relationships

A semantic view is metadata. It copies nothing and moves nothing, so this
chapter models **the gold layer the book already built** rather than a parallel
star assembled for the occasion. A chapter arguing that semantic views are
zero-copy metadata over the warehouse you already have cannot demonstrate that
over a duplicate.

| Logical table | Physical object | Origin |
|---|---|---|
| `transactions` | `gold_db.transactions.fact_transactions` | Chapter 5, topped up here |
| `refunds` | `gold_db.transactions.fact_refunds` | New in Chapter 12 |
| `customers` | `gold_db.customers.dim_customers_current` | New view over the Chapter 5 SCD2 dimension |
| `merchants` | `gold_db.merchants.dim_merchants` | New in Chapter 12 |

Relationships: `txn_to_customer`, `txn_to_merchant`, and `refund_to_txn`. The
third one is why the model carries two grains: one payment can be refunded more
than once, so refunds are events in their own table, not a column on the
payment. The `refunded_amount` fact reaches across that relationship with
`ZEROIFNULL(SUM(refunds.refund_amount))` — without `ZEROIFNULL` every
unrefunded payment nets to null. Snowflake will not let a fact on
`transactions` read the physical `refunds.refund_amount` column; the
DDL declares `PRIVATE refunds.refund_amount AS refund_amount` first
and SUMs that fact. The private fact does not appear in
`SHOW SEMANTIC FACTS`.

`gold_db.semantic` holds the `techflow_revenue` semantic view and the one-tool
`techflow_revenue_agent`. Their definitions live here; the data stays in the
four gold-layer source objects above.

## Reversibility contract

The setup writes into two tables earlier chapters own. Both writes are tagged:

| Table | Marker | Reversed by |
|---|---|---|
| `gold_db.transactions.fact_transactions` | `transaction_id` prefix `TXN-CH12-` | targeted `DELETE` |
| `gold_db.customers.dim_customers` | `record_hash` = `CH12-SEED` or `CH12-BACKFILL` | targeted `DELETE` |

Everything else Chapter 12 creates is chapter-owned and dropped outright. There
is **no `DROP SCHEMA ... CASCADE`** anywhere; the two chapter-owned schemas are
dropped with `RESTRICT` so the statement fails loudly if something unexpected
is still inside.

`chapter12_0_setup.sql` deletes its own tagged rows before inserting, so
re-running it is safe and does not double the fixture.

**While the Chapter 12 rows are present, earlier chapters print different
numbers.** That is the cost of modeling the warehouse you have instead of a
copy. Run the teardown before returning to a Chapter 5, 6, or 9 example.

## Two Chapter 5 interactions worth knowing

1. **`chapter5_1_window_functions.sql` opens with `TRUNCATE TABLE
   gold_db.transactions.fact_transactions`.** Re-running that Chapter 5 file
   destroys the Chapter 12 top-up. Re-run `chapter12_0_setup.sql` afterwards.
2. **Chapter 5 seeds `transaction_ts` relative to `CURRENT_TIMESTAMP()`**, so
   its rows land near the date that script ran. They add a month to the
   Chapter 12 window (2025-01-01 to 2026-07-01) only if that date falls
   outside it. The book account returned 17 months from February 2025 onward. Chapter 5 also
   references nine customer ids its own SCD Type 2 flow never loads into
   `dim_customers`; section 3 of the setup backfills them so the orphan checks
   can return zero.

## Determinism

Every column in the top-up derives from `HASH(seq, '<salt>')` over a gap-free
`ROW_NUMBER`, with timestamps generated inside explicit bounds. The
`ROW_NUMBER` wrapper matters because `SEQ8` alone does not guarantee a gap-free
sequence. Re-running the setup produces the identical dataset on any warehouse,
so metric values are stable across runs. If you change the bounds or the row
count, expect the chapter's figures to shift.

Fixture shape after setup:

| Object | Rows | Note |
|---|---|---|
| `fact_transactions` (Chapter 12 rows) | 50,000 | 88% COMPLETED, 3% REFUNDED, 5% FAILED, 4% PENDING |
| `fact_refunds` | ~2,250 | 1-2 events per REFUNDED payment, 50-100% of the capture |
| `dim_customers` (`CH12-SEED`) | 500 | current versions |
| `dim_customers` (`CH12-BACKFILL`) | 9 | with the stock Chapter 5 fixture |
| `dim_merchants` | 47 | 40 Chapter 12 + 7 Chapter 5 |

Amount tiers: 95% $5-$150, 4.5% $150-$1,500, 0.5% $1,500-$9,000. The long tail
is what gives the `high_value_threshold` exercises something to find.

## Metric contracts

Every metric is validated against an independently written aggregation before
it is exposed. Run the matching set at each stage rather than validating once
at the end, so a failure points at the change that caused it.

| Stage | Where | Contracts |
|---|---|---|
| 3 metrics | `chapter12_2_create_view.sql` | 3 |
| 7 metrics + window | `chapter12_2_create_view.sql` | 6 + 1 |
| 8 metrics | `chapter12_5_coco.sql` | 7 |

Write the manual side from the business definition, not by copying the view's
DDL, or the comparison proves nothing.

## Editor metadata in DDL

Every semantic-view field the chapter adds in the Snowsight editor also has a
DDL clause, so this directory rebuilds the finished object from code alone.

| Editor field | DDL clause | File |
|---|---|---|
| Custom instruction | `AI_SQL_GENERATION` | `chapter12_4_agent_backing.sql` |
| Sample values | `SAMPLE_VALUES` on a dimension or fact | `chapter12_4_agent_backing.sql` |
| Enum flag | `IS_ENUM` on a dimension | `chapter12_4_agent_backing.sql` |
| Verified query | `AI_VERIFIED_QUERIES` | `chapter12_4_agent_backing.sql` |

`SAMPLE_VALUES` and `IS_ENUM` became `CREATE SEMANTIC VIEW` clauses in June
2026; before that they were YAML-only. Within a dimension `SAMPLE_VALUES` must
come first, and `IS_ENUM` is valid on dimensions only. Sample values are stored
as plain metadata and are **not** covered by masking policies on the underlying
columns, so never list values from a sensitive column.

Clause order Snowflake enforces: `TABLES`, `RELATIONSHIPS`, `VARIABLES`,
`FACTS`, `DIMENSIONS`, `METRICS`, `COMMENT`, `AI_SQL_GENERATION`,
`AI_VERIFIED_QUERIES`, `COPY GRANTS`.

`COMMENT` takes an equals sign on every element, **including variables**.
The documented `variableDef` grammar is `[ COMMENT '<description>' ]` with
no equals sign; Snowflake 10.28.101 rejects that form with a syntax error
on the string literal. `VARIABLE_COMMENT_TAKES_EQUALS` in
`chapter12_static_checks.py` is `True`.

## Deployment verbs

`chapter12_2_create_view.sql` stage 1 uses `CREATE OR REPLACE` because it
creates the object and no consumer has been granted anything yet. Every
statement after it uses `CREATE OR ALTER`, which converges the object to the
statement submitted while preserving privileges already granted on it, with no
`COPY GRANTS` clause. `CREATE OR REPLACE` drops those grants unless you append
`COPY GRANTS` explicitly.

Both verbs converge, so an element left out of either one is removed from the
view. That is why every stage repeats the whole definition rather than only its
additions.

## Verification status

**Verified 2026-08-16** against the book account (Snowflake 10.28.101).
`chapter12_0_setup.sql` through `chapter12_5_coco.sql` ran end to end.
Every metric contract returned PASS (3 + 6 + window + 7).
`techflow_revenue.yaml` was regenerated from
`SYSTEM$READ_YAML_FROM_SEMANTIC_VIEW`. The validate-only
`SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(..., TRUE)` call accepted that
export. `chapter12_teardown.sql` restored the pre-chapter fact and
dimension counts (`ch12_fact_rows = 0`, `ch12_dim_rows = 0`; this
account's Chapter 5 leftover is 24 fact rows / 3 dim rows, not the
stock 19).

Two syntax corrections from this run, now in the files:

- A fact cannot read a physical column on another logical table.
  `PRIVATE refunds.refund_amount AS refund_amount` must be declared
  before `ZEROIFNULL(SUM(refunds.refund_amount))`.
- Variable `COMMENT` needs `=`. The documented `variableDef` grammar
  omits it; 10.28.101 rejects the bare form.

Two platform behaviours from 2026-07-26 (10.25.102) still hold:

- **Grant preservation.** With two privileges granted to a test role,
  `CREATE OR ALTER` kept both, `CREATE OR REPLACE ... COPY GRANTS` kept both,
  and the same statement without `COPY GRANTS` silently dropped both.
- **`CREATE OR ALTER` accepts `VARIABLES`, `SAMPLE_VALUES`, and `IS_ENUM`**,
  none of which appear in its documented syntax block. It reports
  `Statement executed successfully` rather than naming the object.

Fixture monetary components on this account (deterministic Chapter 12
top-up plus 24 leftover Chapter 5 fact rows):

| Component | Value |
|---|---|
| `completed_gross` / dashboard | 6,140,173.63 |
| `refunded_captures` | 184,026.45 |
| `refunds_returned` | 141,334.92 |
| `failed_and_pending` | 640,791.56 |
| `all_status_gross` | 6,964,991.64 |
| finance / `total_revenue` | 6,182,865.16 |
| `average_transaction_value` | 139.26 |
| `transaction_count` | 50,024 |
| `fact_refunds` | 2,148 |
| `dim_merchants` | 47 |

## Agent migration checks (September 2026)

**Executed 2026-09-07 using SnowCLI 3.16.0, connection `book`, Snowflake 10.31.103.**
Sections 1, 3, 4, and 5 ran against the existing fixture, and the stage-2
contracts passed (6 + window), followed by all 7 final non-window contracts.
Setup, initial view recreation, teardown, and interactive CoCo generation were
not repeated. The final agent and eight-metric view remain available.

Three live questions were tested through `SNOWFLAKE.CORTEX.DATA_AGENT_RUN`.
After correction, monthly and category SQL used `SEMANTIC_VIEW` and matched
independent SQL to the cent. The monthly rolling query returned 10 populated
months, September 2025–June 2026, totaling $3,407,093.61. The category answer
retained all 10 labels. The dispute question identified missing timestamps
and executed no SQL. The agent's orchestration instruction requests semantic
SQL and unchanged category labels; inspect every new run because generation
can vary.

The verified query now derives the last 12 complete months from `CURRENT_DATE`
in both section 4 and section 5. Its former fixed July 2025–June 2026 range
overrode the rolling instruction. `techflow_revenue.yaml` was re-exported from
the final view and accepted by the validation-only import procedure.

The Table 12.2 grants passed under a temporary non-owner role with secondary
roles disabled. Query history confirms the generated SQL used that role. No
REFERENCES, OWNERSHIP, or MONITOR privilege was required for this SQL-function
test. The temporary role
was removed; the user's defaults were unchanged. Snowsight's default-role
configuration and screenshot captures remain UI checks.

For screenshots, open `GOLD_DB.SEMANTIC.TECHFLOW_REVENUE_AGENT` in Snowsight,
ask the monthly question in a new conversation, and expand `system_execute_sql`.
Then capture the view editor's instruction and `monthly_total_revenue` entry.

`CORTEX_USER` follows the chapter's chosen prerequisites; Snowflake also offers
`CORTEX_AGENT_USER` for roles limited to agents. The consumer template grants
`SELECT`, without `REFERENCES`, on the semantic view. Inspecting/exporting its
definition and monitoring agent traces are separate reviewer privileges.

Historical review notes retain the former section 4 filename; the current
script is `chapter12_4_agent_backing.sql`.
