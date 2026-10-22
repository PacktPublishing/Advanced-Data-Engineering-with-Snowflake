# Chapter 12 CoCo Conventions

CoCo reads this file at the start of every session run from this directory.
It pins the rules for working on the TechFlow semantic layer.

## The model

- The only semantic view in scope is `gold_db.semantic.techflow_revenue`.
- **The view sits on the real gold layer, not a chapter-owned copy.** Its four
  logical tables map to `gold_db.transactions.fact_transactions`,
  `gold_db.transactions.fact_refunds`, `gold_db.customers.dim_customers_current`,
  and `gold_db.merchants.dim_merchants`. Reference those objects by their real
  names. `gold_db.semantic` holds the view and its one-tool revenue agent, so never
  point a logical table or a validation query at a table in that schema.
- Three relationships: `txn_to_customer`, `txn_to_merchant`, and
  `refund_to_txn`. The model spans two grains on purpose. One payment can be
  refunded more than once, so refunds are events in their own table.
- Revenue means captured payments net of refunds, in USD. The money logic lives
  in the `gross_captured_amount`, `refunded_amount`, and `net_amount` facts.
  Never re-derive status or refund logic inside a metric; compose the existing
  facts.
- A fact that reaches across a relationship to a lower-grain table wraps the
  aggregate in `ZEROIFNULL`. Without it, a payment with no refunds returns no
  child rows and nets to null. Snowflake forbids a fact from reading a
  physical column on another logical table: declare
  `PRIVATE refunds.refund_amount AS refund_amount` first, then SUM that
  fact. Do not drop the private fact when regenerating the definition.

## Working rules

- Generate candidates only. Never execute DDL or DML. Output the full
  `CREATE OR ALTER SEMANTIC VIEW` statement for human review. That verb keeps
  the privileges consumers already hold, so no `COPY GRANTS` clause is needed;
  `CREATE OR REPLACE` without one silently revokes them.
- Every candidate must carry forward the complete current definition: tables,
  relationships, variables, facts, dimensions, metrics, comments, synonyms,
  sample values (`SAMPLE_VALUES`), enum flags (`IS_ENUM`), the SQL-generation
  instruction (`AI_SQL_GENERATION`), and the verified queries
  (`AI_VERIFIED_QUERIES`). Every one of these is a DDL clause, so there is no
  excuse for losing one. Dropping an element is a defect, and the verb does not
  save you: `CREATE OR ALTER` converges the object to the statement submitted.
- Tags are the exception. `CREATE OR ALTER` cannot add or change them and
  preserves any that exist, so never emit a `TAG` clause in a candidate.
- Clause order is enforced: `TABLES`, `RELATIONSHIPS`, `VARIABLES`, `FACTS`,
  `DIMENSIONS`, `METRICS`, `COMMENT`, `AI_SQL_GENERATION`,
  `AI_VERIFIED_QUERIES`, `COPY GRANTS`.
- Within a dimension, `SAMPLE_VALUES` precedes `IS_ENUM`. `IS_ENUM` is valid on
  dimensions only, never on facts. Never add sample values to a dimension over
  a sensitive column: they are plain metadata and masking policies do not cover
  them.
- `COMMENT` takes an equals sign on every element, including variables.
  The documented `variableDef` grammar is `[ COMMENT '<description>' ]` with
  no equals sign; Snowflake 10.28.101 rejects that form. Write
  `COMMENT = '...'` inside `VARIABLES (...)` as well.
- Every new metric ships with a validation query that recomputes it with plain
  SQL from `gold_db.transactions.fact_transactions` and
  `gold_db.transactions.fact_refunds`, written from the business definition
  rather than from the view DDL.
- A metric cannot call another metric outside a window function. Repeat the
  expression instead.
- A window metric's `PARTITION BY`, `PARTITION BY EXCLUDING`, and `ORDER BY`
  clauses may only name dimensions the query will request, so state that
  requirement in any comment you generate for one.
- Ratios use `DIV0`. Distinct customer counts filter to captured payments,
  which means `status IN ('COMPLETED', 'REFUNDED')`, matching the revenue facts.
- Metadata (comments, synonyms) applies to eligible elements only: logical
  tables, dimensions, facts, and metrics. Relationships take neither.

## Fixture facts

- Chapter 12 rows in `fact_transactions` carry a `TXN-CH12-` prefix on
  `transaction_id`; Chapter 12 rows in `dim_customers` carry `record_hash` of
  `CH12-SEED` or `CH12-BACKFILL`. Never generate a statement that deletes from
  either table without one of those filters.
- Never generate `DROP SCHEMA ... CASCADE` against `gold_db.transactions` or
  `gold_db.customers`. Both are shared with earlier chapters.
- The seeded window is 2025-01-01 to 2026-07-01. Use explicit bounds for
  fixture-specific comparisons. The agent default and its verified query
  intentionally use `CURRENT_DATE` for the last 12 complete months; never
  replace those rolling bounds with fixture dates.

## Naming

- Metrics: snake_case business terms (`total_revenue`, `refund_rate`).
- Synonyms carry the finance team's vocabulary, not schema vocabulary.
- Comments state the business definition and the unit, not the SQL.
