-- =============================================================================
-- Chapter 5: Advanced SQL Transformations — Shared Setup
-- Run this ONCE, before any chapter5_N_*.sql section script.
--
-- Prerequisites:
--   - Run setup/snowflake_setup.sql (creates UTIL db, BOOK_WH).
--   - Chapters 2-4 completed (RAW_DB, SILVER_DB exist; SILVER_DB.CUSTOMERS.customer
--     integration table from Chapter 4 §5.2).
--
-- Note on naming and layers (medallion convention used throughout the book):
--   - silver_db: integration layer, clean per-entity records, singular nouns
--                (customer, transaction, bill_of_materials).
--   - gold_db:   analytics layer, Kimball-style facts and dimensions, plural
--                nouns (fact_transactions, dim_customers, dim_diagnosis_codes).
--
-- This script bootstraps only databases and schemas. Each section script
-- (chapter5_1 ... chapter5_5) creates its own tables and embeds its own
-- sample data, so a section runs standalone from top to bottom.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;

-- New analytics-layer database introduced in Chapter 5.
CREATE DATABASE IF NOT EXISTS gold_db
    COMMENT = 'Gold layer: Kimball facts and dimensions for analytics';

-- raw_db + silver_db already exist from Chapter 4. Add the missing schemas.
CREATE SCHEMA IF NOT EXISTS raw_db.crm;
CREATE SCHEMA IF NOT EXISTS raw_db.billing;
CREATE SCHEMA IF NOT EXISTS raw_db.streaming;

-- Silver-layer reference schema for the bill_of_materials graph example.
CREATE SCHEMA IF NOT EXISTS silver_db.reference
    COMMENT = 'Silver reference tables (bill of materials, etc.)';

-- Gold-layer schemas referenced by this chapter.
CREATE SCHEMA IF NOT EXISTS gold_db.transactions
    COMMENT = 'Gold transaction fact + window function examples';
CREATE SCHEMA IF NOT EXISTS gold_db.reference
    COMMENT = 'Gold reference / dimension tables (ICD-10, etc.)';
CREATE SCHEMA IF NOT EXISTS gold_db.claims
    COMMENT = 'Gold claims fact for MedCore recursive CTE examples';
CREATE SCHEMA IF NOT EXISTS gold_db.customers
    COMMENT = 'Gold customer dimensions (SCD Type 2, customer 360)';
