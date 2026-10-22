-- =============================================================================
-- Chapter 5 — Section 1: Applying Window Functions for Analytics and Fraud
-- Detection. Standalone: run chapter5_0_setup.sql once first, then this file
-- top to bottom. Sample data is embedded below the DDL.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;


-- =============================================================================
-- 1.1 Building the Transaction Fact Table
-- =============================================================================
--
-- Plural noun (fact_transactions) signals a gold-layer collection built for
-- downstream queries. The risk_score and channel columns drive the
-- fraud-velocity and ranking queries below. risk_score stays NUMBER(5,2):
-- the two decimal places mirror the fractional scores upstream ML models emit.

CREATE OR REPLACE TABLE gold_db.transactions.fact_transactions (
    transaction_id    STRING        NOT NULL,
    customer_id       STRING        NOT NULL,
    merchant_id       STRING        NOT NULL,
    amount            NUMBER(12,2)  NOT NULL,
    currency          STRING        DEFAULT 'USD',
    transaction_ts    TIMESTAMP_NTZ NOT NULL,
    category          STRING,
    channel           STRING,
    status            STRING        DEFAULT 'COMPLETED',
    risk_score        NUMBER(5,2),
    ingested_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_transactions PRIMARY KEY (transaction_id)
);


-- =============================================================================
-- Sample data for this section
-- =============================================================================
--
--   * Customer CUST_FRAUD fires 6 txns in ~3 minutes (velocity burst, §1.2)
--   * Customer CUST_NORMAL fires 2 txns well-spaced (should not alert)
--   * Merchants span GROCERY / ELECTRONICS / TRAVEL for the ranking query (§1.3)
--   * MERCH_GAP has hourly activity then a 4-hour gap for §1.4
--   * C1001-C1003 rows also feed the Chapter 6 gold_customer_value model

TRUNCATE TABLE gold_db.transactions.fact_transactions;

INSERT INTO gold_db.transactions.fact_transactions
    (transaction_id, customer_id, merchant_id, amount, currency,
     transaction_ts, category, channel, status, risk_score)
VALUES
    -- Velocity burst (within the last 24h window)
    ('T0001', 'CUST_FRAUD',  'MERCH_GROC_1', 250.00, 'USD',
        DATEADD('minute', -20, CURRENT_TIMESTAMP()), 'GROCERY',     'MOBILE', 'COMPLETED', 12.5),
    ('T0002', 'CUST_FRAUD',  'MERCH_GROC_1', 340.00, 'USD',
        DATEADD('minute', -19, CURRENT_TIMESTAMP()), 'GROCERY',     'MOBILE', 'COMPLETED', 18.0),
    ('T0003', 'CUST_FRAUD',  'MERCH_ELEC_1', 420.00, 'USD',
        DATEADD('minute', -18, CURRENT_TIMESTAMP()), 'ELECTRONICS', 'WEB',    'COMPLETED', 40.0),
    ('T0004', 'CUST_FRAUD',  'MERCH_ELEC_1', 180.00, 'USD',
        DATEADD('minute', -17, CURRENT_TIMESTAMP()), 'ELECTRONICS', 'WEB',    'COMPLETED', 55.0),
    ('T0005', 'CUST_FRAUD',  'MERCH_TRVL_1', 900.00, 'USD',
        DATEADD('minute', -16, CURRENT_TIMESTAMP()), 'TRAVEL',      'API',    'COMPLETED', 75.0),
    ('T0006', 'CUST_FRAUD',  'MERCH_TRVL_1', 150.00, 'USD',
        DATEADD('minute', -15, CURRENT_TIMESTAMP()), 'TRAVEL',      'API',    'COMPLETED', 80.0),

    -- Normal customer (well-spaced)
    ('T0100', 'CUST_NORMAL', 'MERCH_GROC_2',  45.00, 'USD',
        DATEADD('hour',   -5, CURRENT_TIMESTAMP()), 'GROCERY',     'POS',    'COMPLETED', 5.0),
    ('T0101', 'CUST_NORMAL', 'MERCH_GROC_2',  78.50, 'USD',
        DATEADD('hour',   -2, CURRENT_TIMESTAMP()), 'GROCERY',     'POS',    'COMPLETED', 3.0),

    -- Ranking fodder: multiple merchants per category in current month
    ('T0200', 'CUST_A', 'MERCH_GROC_1', 1200.00, 'USD',
        DATEADD('day', -3, CURRENT_TIMESTAMP()), 'GROCERY', 'WEB', 'COMPLETED', 2.0),
    ('T0201', 'CUST_B', 'MERCH_GROC_2',  800.00, 'USD',
        DATEADD('day', -3, CURRENT_TIMESTAMP()), 'GROCERY', 'WEB', 'COMPLETED', 2.0),
    ('T0202', 'CUST_C', 'MERCH_GROC_3',  600.00, 'USD',
        DATEADD('day', -2, CURRENT_TIMESTAMP()), 'GROCERY', 'POS', 'COMPLETED', 1.0),
    ('T0203', 'CUST_D', 'MERCH_ELEC_1', 2500.00, 'USD',
        DATEADD('day', -4, CURRENT_TIMESTAMP()), 'ELECTRONICS', 'WEB', 'COMPLETED', 10.0),
    ('T0204', 'CUST_E', 'MERCH_ELEC_2', 1800.00, 'USD',
        DATEADD('day', -4, CURRENT_TIMESTAMP()), 'ELECTRONICS', 'WEB', 'COMPLETED', 8.0),
    ('T0205', 'CUST_F', 'MERCH_TRVL_1', 3200.00, 'USD',
        DATEADD('day', -5, CURRENT_TIMESTAMP()), 'TRAVEL', 'API', 'COMPLETED', 15.0),

    -- Gap merchant: hourly activity, then a 4-hour silence, then resumes
    ('T0300', 'CUST_G', 'MERCH_GAP', 50.00, 'USD',
        DATEADD('hour', -10, CURRENT_TIMESTAMP()), 'GROCERY', 'POS', 'COMPLETED', 1.0),
    ('T0301', 'CUST_G', 'MERCH_GAP', 50.00, 'USD',
        DATEADD('hour',  -9, CURRENT_TIMESTAMP()), 'GROCERY', 'POS', 'COMPLETED', 1.0),
    ('T0302', 'CUST_G', 'MERCH_GAP', 50.00, 'USD',
        DATEADD('hour',  -8, CURRENT_TIMESTAMP()), 'GROCERY', 'POS', 'COMPLETED', 1.0),
    -- 4-hour gap (hours -7..-4 silent)
    ('T0303', 'CUST_H', 'MERCH_GAP', 50.00, 'USD',
        DATEADD('hour',  -3, CURRENT_TIMESTAMP()), 'GROCERY', 'POS', 'COMPLETED', 1.0),
    ('T0304', 'CUST_H', 'MERCH_GAP', 50.00, 'USD',
        DATEADD('hour',  -2, CURRENT_TIMESTAMP()), 'GROCERY', 'POS', 'COMPLETED', 1.0),

    -- Chapter 6 join fodder: transactions for the CRM customers (C1001-C1003)
    ('T0400', 'C1001', 'MERCH_GROC_1', 320.00, 'USD',
        DATEADD('day', -1, CURRENT_TIMESTAMP()), 'GROCERY',     'WEB',    'COMPLETED', 4.0),
    ('T0401', 'C1001', 'MERCH_ELEC_1', 980.00, 'USD',
        DATEADD('day', -6, CURRENT_TIMESTAMP()), 'ELECTRONICS', 'WEB',    'COMPLETED', 9.0),
    ('T0402', 'C1002', 'MERCH_TRVL_1', 1450.00, 'USD',
        DATEADD('day', -2, CURRENT_TIMESTAMP()), 'TRAVEL',      'API',    'COMPLETED', 11.0),
    ('T0403', 'C1003', 'MERCH_GROC_2', 75.50, 'USD',
        DATEADD('day', -4, CURRENT_TIMESTAMP()), 'GROCERY',     'POS',    'COMPLETED', 2.0),
    ('T0404', 'C1003', 'MERCH_GROC_2', 60.00, 'USD',
        DATEADD('hour', -8, CURRENT_TIMESTAMP()), 'GROCERY',    'POS',    'COMPLETED', 1.5);


-- =============================================================================
-- 1.2 Detecting Fraudulent Transaction Velocity
-- =============================================================================
--
-- Snowflake has no named-window clause, so COUNT and SUM each carry the full
-- OVER specification even though the frame is identical.
-- Expected on the seed: 4 rows, all CUST_FRAUD, MEDIUM -> HIGH as the
-- 5-minute window fills up.

WITH velocity AS (
    SELECT
        transaction_id,
        customer_id,
        merchant_id,
        amount,
        transaction_ts,
        COUNT(*) OVER (
            PARTITION BY customer_id
            ORDER BY transaction_ts
            RANGE BETWEEN INTERVAL '5 MINUTES' PRECEDING
                      AND CURRENT ROW
        ) AS txn_count_5min,
        SUM(amount) OVER (
            PARTITION BY customer_id
            ORDER BY transaction_ts
            RANGE BETWEEN INTERVAL '5 MINUTES' PRECEDING
                      AND CURRENT ROW
        ) AS total_amount_5min
    FROM gold_db.transactions.fact_transactions
    WHERE transaction_ts >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
)
SELECT
    transaction_id,
    customer_id,
    merchant_id,
    amount,
    transaction_ts,
    txn_count_5min,
    total_amount_5min,
    CASE
        WHEN txn_count_5min >= 5 AND total_amount_5min > 1000 THEN 'HIGH'
        WHEN txn_count_5min >= 3 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS velocity_risk
FROM velocity
WHERE txn_count_5min >= 3
ORDER BY customer_id, transaction_ts;


-- =============================================================================
-- 1.3 Ranking Merchants by Revenue
-- =============================================================================
--
-- Expected on the seed: seven rows, one per (category, month, merchant);
-- revenue_share sums to 1.0 within each category.

SELECT
    merchant_id,
    category,
    DATE_TRUNC('month', transaction_ts)                  AS revenue_month,
    SUM(amount)                                          AS monthly_revenue,
    DENSE_RANK() OVER (
        PARTITION BY category, DATE_TRUNC('month', transaction_ts)
        ORDER BY SUM(amount) DESC
    )                                                    AS category_rank,
    SUM(amount) / SUM(SUM(amount)) OVER (
        PARTITION BY category, DATE_TRUNC('month', transaction_ts)
    )                                                    AS revenue_share
FROM gold_db.transactions.fact_transactions
WHERE status = 'COMPLETED'
GROUP BY merchant_id, category, DATE_TRUNC('month', transaction_ts)
ORDER BY category, revenue_month DESC, category_rank;


-- =============================================================================
-- 1.4 Identifying Gaps in Time-Series Data
-- =============================================================================
--
-- with_prev evaluates LAG() once; gaps derives the hour difference from it,
-- so the window specification appears a single time (TR feedback, 2026-08).
-- Expected on the seed: MERCH_GAP shows hours_since_last = 5.

WITH hourly_activity AS (
    SELECT
        merchant_id,
        DATE_TRUNC('hour', transaction_ts) AS activity_hour,
        COUNT(*)                           AS txn_count
    FROM gold_db.transactions.fact_transactions
    GROUP BY merchant_id, DATE_TRUNC('hour', transaction_ts)
),
with_prev AS (
    SELECT
        merchant_id,
        activity_hour,
        txn_count,
        LAG(activity_hour) OVER (
            PARTITION BY merchant_id
            ORDER BY activity_hour
        ) AS prev_hour
    FROM hourly_activity
),
gaps AS (
    SELECT
        merchant_id,
        activity_hour,
        txn_count,
        prev_hour,
        DATEDIFF('hour', prev_hour, activity_hour) AS hours_since_last
    FROM with_prev
)
SELECT *
FROM gaps
WHERE hours_since_last > 2
ORDER BY merchant_id, activity_hour;


-- =============================================================================
-- 1.5 Calculating Running Totals Across Time and Partition
-- =============================================================================

-- Year-to-date revenue by merchant, month-grain.
-- YEAR(transaction_ts) inside PARTITION BY resets the YTD counter on Jan 1.
SELECT
    merchant_id,
    DATE_TRUNC('month', transaction_ts) AS revenue_month,
    SUM(amount)                         AS monthly_revenue,
    SUM(SUM(amount)) OVER (
        PARTITION BY merchant_id, YEAR(transaction_ts)
        ORDER BY DATE_TRUNC('month', transaction_ts)
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS ytd_revenue
FROM gold_db.transactions.fact_transactions
WHERE status = 'COMPLETED'
GROUP BY merchant_id, DATE_TRUNC('month', transaction_ts), YEAR(transaction_ts)
ORDER BY merchant_id, revenue_month;

-- Per-customer cumulative spend and transaction count, transaction-grain.
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW is the canonical
-- running-total frame; deterministic under ties (compare with RANGE).
SELECT
    transaction_id,
    customer_id,
    transaction_ts,
    amount,
    SUM(amount) OVER (
        PARTITION BY customer_id
        ORDER BY transaction_ts
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_spend,
    COUNT(*) OVER (
        PARTITION BY customer_id
        ORDER BY transaction_ts
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_transaction_count
FROM gold_db.transactions.fact_transactions
WHERE status = 'COMPLETED'
ORDER BY customer_id, transaction_ts;
