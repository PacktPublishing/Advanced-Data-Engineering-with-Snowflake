-- =============================================================================
-- Chapter 14: Data Modeling in Snowflake using AI-Assisted Practices
-- Section 6: Accelerating modeling work with Snowflake CoCo
-- Advanced Snowflake Data Engineering (Packt, 2026)
--
-- Covers: 6.1 Loading the modeling conventions into CoCo, 6.2 Drafting the
-- design and the SCD code, 6.3 Reviewing and validating generated models.
-- This file is the reviewed OUTCOME of the CoCo session, not a transcript:
-- block 1 the grain comments the third prompt produced, block 2 the invariants
-- view the chapter creates, block 3 the manual run of the checks, which closes
-- the file. Scheduling the checks is Chapter 16's subject (an alert whose
-- action writes an incident log, with the ALERT_HISTORY read that proves it
-- ran); this chapter keeps the view as the one definition such a schedule
-- would read.
--
-- Prerequisites: chapter14_0_setup.sql and chapter14_2_scd_patterns.sql (the
-- checks read the dimension state section 3 leaves behind; they pass on an
-- untouched Chapter 12 dimension as well). Section 2 is needed only for the
-- calendar and star-view comments, which error harmlessly if those objects
-- are missing.
--
-- Role convention: SYSADMIN. COMMENT ON is an ALTER, so block 1 needs
-- OWNERSHIP of all four commented tables (fact_transactions, fact_refunds,
-- dim_customers, dim_merchants), and block 2 needs CREATE VIEW on
-- gold_db.customers.
--
-- Rerun-safe: the DDL is CREATE OR REPLACE and the COMMENT ON statements are
-- idempotent, so the file can run again after a teardown or on its own.
--
-- Placeholder convention: <REPLACE: ...>. This file has none.
--
-- CoCo session conventions for this directory live in AGENTS.md; the
-- scd-dimension skill lives in .cortex/skills/scd-dimension/SKILL.md. Start the
-- session from chapters/chapter14 so both load, and confirm with /skill list.
--
-- THE PROMPTS (comment blocks the chapter cites by name; the agent never
-- executes anything against the account):
--
-- The design-draft prompt (6.2, describe before propose):
--
--   First reverse-engineer the existing gold layer from the CREATE
--   TABLE statements below: one grain sentence per table and a map
--   of facts against dimensions, as it stands today. Wait for my
--   corrections. Then, using the six questions finance and support
--   ask monthly, propose the target design: the dimensions each
--   question needs and an SCD policy per dimension attribute with a
--   one-line reason. Flag any question the design cannot answer, and
--   do not execute anything.
--
--   Paste GET_DDL output for fact_transactions, fact_refunds, dim_customers,
--   dim_merchants, and dim_date below the prompt, then the six questions:
--     1. Monthly captured revenue by merchant category, last 18 months.
--     2. Revenue by customer state at the time of payment.
--     3. Refund rate by channel, by quarter.
--     4. Weekend versus weekday payment mix.
--     5. Merchants whose category changed this year, reported both ways.
--     6. Distinct paying customers per month.
--
--   The current-state map CoCo returns first opens with one grain sentence
--   per table (the chapter shows this excerpt, composed from the reviewed
--   grain comments in block 1, so your session's wording will differ):
--
--   fact_transactions: one row per payment attempt, all statuses.
--   fact_refunds: one row per refund event. A payment can carry several.
--   dim_customers: one row per customer version (SCD Type 2).
--   dim_merchants: one row per merchant, category overwritten in place.
--
--   The last line is the one to correct before continuing: dim_merchants
--   keeps the prior category in previous_category during the reclassification.
--
--   Run CoCo in plan mode for this session (/plan before the first prompt,
--   or start the CLI with --plan): it then presents its intended actions and
--   waits for approval instead of acting. In its default confirm mode CoCo
--   auto-approves read-only SQL such as SELECT and SHOW and prompts before
--   INSERT, UPDATE, DELETE, and CREATE, so the "do not execute anything" line
--   in each prompt is a second guard, not the only one
--   (https://docs.snowflake.com/en/user-guide/cortex-code/security).
--
-- The skill prompt (6.2, plan-first):
--
--   $scd-dimension Write a plan, as a markdown file with a checkbox
--   per step, for generating the batch close-and-insert pair for
--   gold_db.customers.dim_customers reading
--   raw_db.crm.stg_customer_extract, following AGENTS.md conventions,
--   inside one explicit transaction, plus the invariant validation
--   queries. Put any question for me inside the plan. After my
--   approval, execute the plan one step at a time, marking each
--   checkbox. Do not run any SQL against the account.
--
--   The plan the skill writes (plan file plans/dim_customers_scd2.md):
--     - [ ] 1. Read AGENTS.md hashing and window conventions
--     - [ ] 2. Confirm target columns from DESCRIBE TABLE dim_customers
--     - [ ] 3. Draft the close MERGE (question: extract_ts or CURRENT_TIMESTAMP as effective_to?)
--     - [ ] 4. Draft the anti-join INSERT
--     - [ ] 5. Wrap both in BEGIN/COMMIT
--     - [ ] 6. Draft the five invariant checks as one view
--     - [ ] 7. Diff against chapter14_2_scd_patterns.sql and list differences
--   Answer the step 3 question (extract_ts, so the version boundary is the
--   source's time, not the load's), approve, and the generated pair should
--   match section 3.3 line for line. The reviewed pair is the one in
--   chapter14_2_scd_patterns.sql; it is not duplicated here.
--
-- The metadata prompt (6.2, third prompt):
--
--   Draft COMMENT ON statements for every table and column of the star
--   (fact_transactions, fact_refunds, dim_customers, dim_merchants,
--   dim_date, star_transactions) using payments-finance vocabulary.
--   Every table comment states its grain in one sentence. Do not
--   execute anything.
--
--   The reviewed output is block 1 below.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE BOOK_WH;
USE DATABASE gold_db;


-- =============================================================================
-- 1. Grain comments (reviewed output of the metadata prompt)
-- -----------------------------------------------------------------------------
-- Every table comment opens with its grain sentence. Carry these business
-- descriptions into the semantic view used by the Cortex Agent, following
-- the Chapter 12 pattern.
-- =============================================================================

COMMENT ON TABLE gold_db.transactions.fact_transactions IS
    'One row per payment attempt, all statuses. Captured revenue is COMPLETED plus REFUNDED amounts; refunds live in fact_refunds.';
COMMENT ON TABLE gold_db.transactions.fact_refunds IS
    'One row per refund event; a payment can carry several. Amounts in USD.';
COMMENT ON TABLE gold_db.customers.dim_customers IS
    'One row per customer version (SCD Type 2). Address, name, and email changes create versions. effective_from and effective_to are validity metadata. This lab resolves versions using customer_id and a half-open time window; extract_ts is assumed to be the business-effective boundary.';
COMMENT ON TABLE gold_db.merchants.dim_merchants IS
    'One row per merchant (conformed). merchant_city is Type 1; merchant_category is Type 3 during the electronics-to-retail transition (previous_category holds the prior value).';
COMMENT ON COLUMN gold_db.customers.dim_customers.effective_from IS
    'Inclusive version start in UTC. This fixture assumes extract_ts is the business-effective change time; the field is Type 2 control metadata.';
COMMENT ON COLUMN gold_db.customers.dim_customers.effective_to IS
    'End of the validity window, exclusive, UTC. 9999-12-31 marks the current version.';
COMMENT ON COLUMN gold_db.customers.dim_customers.record_hash IS
    'SHA-256 of the NVL-wrapped, pipe-delimited tracked attributes; equality means no Type 2 change.';
COMMENT ON COLUMN gold_db.merchants.dim_merchants.previous_category IS
    'Alternate merchant classification before the last reclassification. Supports reporting the same payments under two categories; retains one prior value, not event-time history.';

-- Expected: 'Statement executed successfully.' for each COMMENT ON.

-- The star view exists only if chapter14_1_star_schema.sql ran. Snowsight and
-- snow sql stop at the first error, so the comment sits in a block that
-- reports a missing view instead of failing.
EXECUTE IMMEDIATE $$
BEGIN
    COMMENT ON VIEW gold_db.transactions.star_transactions IS
        'One row per payment attempt joined to the calendar and the merchant dimension. Customer attributes are deliberately absent: join dim_customers with the point-in-time pattern.';
    RETURN 'star_transactions commented.';
EXCEPTION
    WHEN STATEMENT_ERROR THEN
        RETURN 'star_transactions not present (section 2 not run); comment skipped.';
END;
$$;

-- Expected: 'star_transactions commented.' after section 2, or the skipped
-- message without it.


-- =============================================================================
-- 2. The invariant checks as one view
-- -----------------------------------------------------------------------------
-- The chapter defines the five Type 2 invariants as a view so the manual check
-- and any scheduled check read one definition. Three details keep the checks
-- honest about what they test: the <> 1 test on COUNT_IF, so a key with zero
-- current versions fails as surely as one with two (Snowflake's COUNT_IF
-- returns 0 for a group with no match, so the COALESCE is only defensive);
-- IS DISTINCT FROM against the sentinel, so a NULL effective_to fails instead
-- of comparing to unknown; and a LAG over each customer's versions, so a hole
-- between two consecutive windows (a gap that moves facts into the 'unknown'
-- bucket of the point-in-time join) is counted. Facts that precede a
-- customer's FIRST version are not a gap in the dimension and stay a data
-- question for the point-in-time query.
-- =============================================================================

CREATE OR REPLACE VIEW gold_db.customers.dim_customers_invariants AS
SELECT 'current_count_not_one' AS check_name, COUNT(*) AS failures
FROM (SELECT customer_id FROM gold_db.customers.dim_customers
      GROUP BY customer_id HAVING COALESCE(COUNT_IF(is_current), 0) <> 1)
UNION ALL
SELECT 'overlapping_windows', COUNT(*)
FROM gold_db.customers.dim_customers a
JOIN gold_db.customers.dim_customers b
  ON a.customer_id = b.customer_id AND a.customer_key < b.customer_key
 AND a.effective_from < b.effective_to AND b.effective_from < a.effective_to
UNION ALL
SELECT 'internal_gap', COUNT(*)
FROM (SELECT effective_from, LAG(effective_to) OVER (
          PARTITION BY customer_id ORDER BY effective_from) AS prev_end
      FROM gold_db.customers.dim_customers)
WHERE prev_end < effective_from
UNION ALL
SELECT 'current_end_not_sentinel', COUNT(*)
FROM gold_db.customers.dim_customers
WHERE is_current AND effective_to IS DISTINCT FROM '9999-12-31'::TIMESTAMP_NTZ
UNION ALL
SELECT 'invalid_window', COUNT(*)
FROM gold_db.customers.dim_customers
WHERE effective_from IS NULL OR effective_to IS NULL
   OR effective_from >= effective_to;

-- Expected: 'View DIM_CUSTOMERS_INVARIANTS successfully created.'


-- =============================================================================
-- 3. The invariant checks, run by hand (the block that closes the chapter)
-- -----------------------------------------------------------------------------
-- One current row per business key (never zero, never two), no overlapping
-- validity windows, no gap between consecutive windows, no current row whose
-- end is not the sentinel, and no window missing a boundary or running
-- backwards. The scd-dimension skill emits these five when asked for
-- validation; whoever wrote the MERGE, the dimension either holds them or it
-- does not.
-- =============================================================================

SELECT check_name, failures
  FROM gold_db.customers.dim_customers_invariants
 ORDER BY check_name;

-- Expected: five rows, every failures value zero. Any nonzero count means the
-- structural history contract is broken. Also verify business attributes and
-- payment attribution around the effective boundary; zero structural failures
-- alone do not prove those business results. To run the check on a schedule,
-- wrap this view in an alert whose action writes to a log table, the pattern
-- chapter16's companion builds and monitors end to end. Run
-- chapter14_teardown.sql when you finish experimenting.
