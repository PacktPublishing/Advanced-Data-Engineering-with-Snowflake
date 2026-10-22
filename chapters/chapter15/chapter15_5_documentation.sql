-- Chapter 15: Documentation and CoCo policy authoring (Packt, 2026)
-- Placeholder convention: book and BOOK_WH are defaults; no SQL placeholders.
-- SQL prerequisite: chapter15_0_setup.sql only. CoCo audit prompts need 1-4.
-- Metadata-only generation uses Cortex credits; no table rows are sampled.
-- GOVERNANCE_OWNER owns lab objects; USERADMIN/ACCOUNTADMIN bootstrap is in setup.
-- Execute SQL top to bottom. Send the named optional prompts separately.
USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;
USE DATABASE governance_db;

CALL AI_GENERATE_TABLE_DESC('governance_db.transactions.fact_refunds',
                            {'describe_columns': TRUE, 'use_table_data': FALSE});
-- Expected: JSON describing the table and columns; descriptions vary.
-- The metadata-only model cannot establish currencies, codes, or timezones.

-- Reviewed comments derived from the fixture definition, not model authority.
ALTER TABLE governance_db.transactions.fact_refunds MODIFY COLUMN refund_amount
    COMMENT 'Amount returned by this refund event, in the associated payment currency';
ALTER TABLE governance_db.transactions.fact_refunds MODIFY COLUMN refund_reason
    COMMENT 'Refund reason: customer request, duplicate charge, item returned, or chargeback';
SELECT column_name, comment
FROM governance_db.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'TRANSACTIONS' AND table_name = 'FACT_REFUNDS'
ORDER BY ordinal_position;
-- Expected: both reviewed comments; the table grain comment is untouched.

-- Documentation maintenance: introduce one explicitly defined new attribute.
ALTER TABLE governance_db.transactions.fact_refunds
    ADD COLUMN processing_channel STRING;
-- NULL means not captured. Proposed values are portal and support.
-- CoCo prompt 1 (documentation generation/maintenance; do not execute):
-- Inspect only INFORMATION_SCHEMA metadata for
-- governance_db.transactions.fact_refunds. Find missing column comments.
-- Draft COMMENT statements, preserving the existing table grain comment.
-- processing_channel means the refund intake route: portal or support;
-- NULL means not captured. Do not sample rows or execute the patch.
-- Mark any business meaning you cannot establish as a question.
-- Exclude unresolved meanings from executable SQL. Do not label a draft
-- safe to apply while its business assumptions remain unverified.
-- Expected: a draft for PROCESSING_CHANNEL among the missing comments;
-- no invented currency, timezone, agent, or change to the grain.

-- Apply the reviewed patch for the new column, then verify the maintenance gap.
ALTER TABLE governance_db.transactions.fact_refunds MODIFY COLUMN processing_channel
    COMMENT 'Refund intake route: portal or support; NULL means not captured';
SELECT column_name, comment
FROM governance_db.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'TRANSACTIONS' AND table_name = 'FACT_REFUNDS'
  AND column_name = 'PROCESSING_CHANNEL';
SELECT comment AS table_grain
FROM governance_db.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'TRANSACTIONS' AND table_name = 'FACT_REFUNDS';
-- Expected: reviewed column text and unchanged Grain: one row per refund...
-- Repeat prompt 1: PROCESSING_CHANNEL must no longer be reported missing.
-- Other undocumented columns remain review items; do not fill them by guesswork.

-- CoCo prompt 2 (policy draft; do not execute):
-- Draft a masking policy for governance_db.transactions.fact_transactions.risk_score.
-- Return the value only when IS_ROLE_IN_SESSION('PII_READER') is true;
-- otherwise return NULL. Use governance_db.policies for the policy.
-- Show CREATE and ALTER TABLE, plus allowed and denied tests with secondary
-- roles disabled. Account for the existing row access policy: if the PII role
-- has no visible rows, identify the missing entitlement instead of claiming
-- a passing test. Do not execute anything or propose grants or entitlement changes.
-- Expected: NUMBER -> NUMBER policy, hierarchy-aware role test, explicit NULL.
-- The PII role has no merchant mapping, so a positive fact-table test needs an
-- explicitly authorized entitlement. Zero rows do not prove correct unmasking.

-- CoCo prompt 3 (classification review; read-only):
-- Compare a dry SYSTEM$CLASSIFY recommendation for
-- governance_db.customers.dim_customers with its pii_category tags.
-- Read column tags with TAG_REFERENCES_ALL_COLUMNS before the dry call;
-- wait for that result, then call SYSTEM$CLASSIFY with {'sample_count': 1000}
-- and no profile. Read column tags again afterward and compare the snapshots.
-- Report differences and confidence; do not retag or broaden masking exceptions.
-- Expected: differences are review items; a particular empty result is not promised.

-- CoCo prompt 4 (quality and access audit; read-only):
-- Identify the latest failed and recovered orphan-merchant expectation in
-- GOVERNANCE_DB, citing UTC timestamps, values, table_id, and metric_id.
-- Inspect the view schemas before constructing queries. Use the checked
-- queries in chapter15_coco_audit.sql as the evidence baseline.
-- Match table_id to creation/deletion metadata; names can be reused after
-- teardown. Do not attribute old measurements to a recreated table.
-- For access to governance_db.customers.dim_customers, join ACCESS_HISTORY
-- to QUERY_HISTORY on query_id. Report user, role_name, secondary_role_stats,
-- accessed columns, and referenced policies. Select qh.secondary_role_stats
-- explicitly; a NULL value is not an absent column. ACCESS_HISTORY can lag
-- up to three hours; QUERY_HISTORY can lag up to 45 minutes.
-- Treat NULL statistics as unknown without corroboration. Report roles
-- evaluated, not a complete active-role list inferred from those statistics.
-- Separate recorded role evidence from historical role membership that these
-- views cannot establish. Do not infer unmasked values from a policy reference.
-- Expected: evidence-linked results or an explicit latency/permission limitation.
