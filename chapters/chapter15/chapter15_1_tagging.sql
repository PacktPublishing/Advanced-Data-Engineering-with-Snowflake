-- Chapter 15: Governance, Security, and Data Quality (Packt, 2026)
-- Placeholder convention: book and BOOK_WH are defaults; no SQL placeholders.
-- Run with Snowflake CLI: snow sql -c book -f <this file>.
-- Requires Enterprise Edition, BOOK_WH, and chapter15_0_setup.sql.
-- Lab scope: GOVERNANCE_DB and the five reserved lab roles only.
-- USERADMIN creates roles; GOVERNANCE_OWNER owns lab objects under SYSADMIN;
-- ACCOUNTADMIN grants account privileges only in setup. No writes to GOLD_DB.
-- Full run order and execution evidence: README.md and VALIDATION.md.

USE ROLE governance_owner;
USE SECONDARY ROLES NONE;
USE WAREHOUSE BOOK_WH;
USE DATABASE governance_db;

-- -----------------------------------------------------------------------------
-- 1.1 step 1: governance database, schemas, and the three-tag taxonomy
-- -----------------------------------------------------------------------------
USE ROLE GOVERNANCE_OWNER;

CREATE TAG governance_db.policies.pii_category
    COMMENT = 'Semantic category written by pii_profile; read by the tag-based masking policies';
CREATE TAG governance_db.policies.data_domain
    ALLOWED_VALUES 'payments', 'customers', 'merchants'
    COMMENT = 'Business domain that owns the object';
CREATE TAG governance_db.policies.data_owner
    COMMENT = 'Named owner accountable for the object, as an email address';

-- Expected: 'successfully created' for each object. SHOW TAGS IN SCHEMA
-- governance_db.policies lists PII_CATEGORY, DATA_DOMAIN, DATA_OWNER.

-- -----------------------------------------------------------------------------
-- 1.1 step 2: propagation for the sensitivity tag
-- -----------------------------------------------------------------------------
ALTER TAG governance_db.policies.pii_category
    SET PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT;

-- Expected: 'Statement executed successfully.'

-- -----------------------------------------------------------------------------
-- 1.1 step 3: domain and owner tags at schema level (inherited downward)
-- -----------------------------------------------------------------------------
ALTER SCHEMA governance_db.transactions SET TAG
    governance_db.policies.data_domain = 'payments',
    governance_db.policies.data_owner  = 'payments-data@techflow.example';
ALTER SCHEMA governance_db.customers SET TAG
    governance_db.policies.data_domain = 'customers',
    governance_db.policies.data_owner  = 'crm-data@techflow.example';
ALTER SCHEMA governance_db.merchants SET TAG
    governance_db.policies.data_domain = 'merchants',
    governance_db.policies.data_owner  = 'partners-data@techflow.example';

-- Expected: 'Statement executed successfully.' three times. A value outside
-- ALLOWED_VALUES fails: "Tag value 'payment' is not allowed".

-- Verification: a table nobody tagged reports both values at level SCHEMA.
SELECT tag_name, tag_value, level
  FROM TABLE(governance_db.INFORMATION_SCHEMA.TAG_REFERENCES(
         'governance_db.customers.dim_customers', 'TABLE'));

-- Expected: two rows, DATA_DOMAIN = customers and DATA_OWNER = the CRM
-- address, both with level = SCHEMA.

-- -----------------------------------------------------------------------------
-- 1.2 step 1: classification profile + tag map
-- -----------------------------------------------------------------------------
-- Change existing profiles with supported methods, such as SET_TAG_MAP
-- or SET_MAXIMUM_CLASSIFICATION_VALIDITY_DAYS; do not replace attached profiles.
CREATE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    governance_db.classification.pii_profile(
  {
    'minimum_object_age_for_classification_days': 0,
    'maximum_classification_validity_days': 30,
    'auto_tag': TRUE,
    'classify_views': FALSE
  });

CALL governance_db.classification.pii_profile!SET_TAG_MAP(
  {
    'column_tag_map': [
      { 'tag_name': 'governance_db.policies.pii_category' }
    ]
  });

-- Expected: 'Instance PII_PROFILE successfully created.' then a confirmation
-- string from SET_TAG_MAP. To read the settings back:
-- SELECT governance_db.classification.pii_profile!DESCRIBE();

-- -----------------------------------------------------------------------------
-- 1.2 step 2: dry scan of the customer dimension (recommendations only,
-- nothing applied)
-- -----------------------------------------------------------------------------
CALL SYSTEM$CLASSIFY('governance_db.customers.dim_customers',
                     {'sample_count': 1000});

-- Expected: one JSON document; classification_result keyed by column with
-- CUSTOMER_NAME -> NAME and EMAIL -> EMAIL (privacy_category IDENTIFIER),
-- ADDRESS_LINE1 / CITY / STATE / POSTAL_CODE -> geographic categories at
-- lower confidence, and no recommendation for CUSTOMER_ID, CUSTOMER_KEY, the
-- timestamps, IS_CURRENT, or RECORD_HASH. No tags are written by this call.

-- -----------------------------------------------------------------------------
-- Review the other three tables. A business-name false positive needs a
-- column-specific exception; never add NAME to the shared pass-through list.
CALL SYSTEM$CLASSIFY('governance_db.merchants.dim_merchants',       {'sample_count': 1000});
CALL SYSTEM$CLASSIFY('governance_db.transactions.fact_transactions', {'sample_count': 1000});
CALL SYSTEM$CLASSIFY('governance_db.transactions.fact_refunds',      {'sample_count': 1000});

-- Expected (stock fixture): MERCHANT_CITY -> CITY; MERCHANT_NAME may receive a
-- NAME recommendation; review it as a possible business-name false positive.
-- Classification results depend on the sampled data.

-- -----------------------------------------------------------------------------
-- OPTIONAL BLOCK: test the custom classifier without attaching it to the
-- automatic profile. Copy the statements to a worksheet to opt in.
-- CREATE SNOWFLAKE.DATA_PRIVACY.CUSTOM_CLASSIFIER
--     governance_db.classification.techflow_ids();
-- CALL governance_db.classification.techflow_ids!ADD_REGEX(
--     SEMANTIC_CATEGORY => 'TECHFLOW_CUSTOMER_ID',
--     PRIVACY_CATEGORY => 'IDENTIFIER',
--     VALUE_REGEX => '^(CUST-CH12-[0-9]{4}|C[0-9]{4})$',
--     COL_NAME_REGEX => '.*CUSTOMER_ID.*',
--     DESCRIPTION => 'TechFlow customer business key');
-- CREATE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
--     governance_db.classification.custom_review({
--       'minimum_object_age_for_classification_days': 0,
--       'maximum_classification_validity_days': 30,
--       'auto_tag': FALSE});
-- CALL governance_db.classification.custom_review!SET_CUSTOM_CLASSIFIERS(
--     {'governance_db.classification.techflow_ids':
--       governance_db.classification.techflow_ids!LIST()});
-- CALL SYSTEM$CLASSIFY('governance_db.customers.dim_customers',
--                      'governance_db.classification.custom_review');
-- Expected: inspect TECHFLOW_CUSTOMER_ID recommendations; no tags applied.
-- Before deploying a key classifier, design and test consistent masking on
-- both sides of every join. A hash is pseudonymization, not anonymization.
