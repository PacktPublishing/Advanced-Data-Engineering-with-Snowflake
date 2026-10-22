-- Cleanup: remove all benchmark scaffolding created for the UDF performance tests.
USE DATABASE GOLD_DB;
USE SCHEMA TRANSACTIONS;

DROP TABLE IF EXISTS gold_db.transactions.fact_transactions_bench;
DROP TABLE IF EXISTS gold_db.transactions.fact_transactions_text_bench;

DROP FUNCTION IF EXISTS gold_db.transactions.classify_risk_tier(FLOAT, FLOAT);
DROP FUNCTION IF EXISTS gold_db.transactions.classify_risk_tier_vec(FLOAT, FLOAT);
DROP FUNCTION IF EXISTS gold_db.transactions.categorize_transaction(STRING);
DROP FUNCTION IF EXISTS gold_db.transactions.categorize_transaction_vec(STRING);
DROP FUNCTION IF EXISTS gold_db.transactions.compute_anomaly_score(FLOAT, FLOAT);
DROP FUNCTION IF EXISTS gold_db.transactions.compute_anomaly_score_vec(FLOAT, FLOAT);
DROP FUNCTION IF EXISTS gold_db.transactions.compute_anomaly_score_vec_b1k(FLOAT, FLOAT);
DROP FUNCTION IF EXISTS gold_db.transactions.compute_anomaly_score_vec_b10k(FLOAT, FLOAT);
DROP FUNCTION IF EXISTS gold_db.transactions.compute_anomaly_score_vec_b50k(FLOAT, FLOAT);
