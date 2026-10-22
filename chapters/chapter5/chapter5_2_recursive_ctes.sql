-- =============================================================================
-- Chapter 5 — Section 2: Navigating Hierarchical Data with Recursive CTEs.
-- Standalone: run chapter5_0_setup.sql once first, then this file top to
-- bottom. Sample data is embedded below each DDL block.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BOOK_WH;


-- =============================================================================
-- 2.1 Building the Diagnosis Code Hierarchy
-- =============================================================================

CREATE OR REPLACE TABLE gold_db.reference.dim_diagnosis_codes (
    code_id       STRING  NOT NULL,
    description   STRING  NOT NULL,
    parent_code   STRING,
    code_level    INT     NOT NULL,
    is_billable   BOOLEAN DEFAULT FALSE,
    category      STRING,
    CONSTRAINT pk_dim_diagnosis_codes PRIMARY KEY (code_id),
    CONSTRAINT fk_parent FOREIGN KEY (parent_code)
        REFERENCES gold_db.reference.dim_diagnosis_codes(code_id)
);

-- Claims fact referenced by the 2.3 aggregation query.
CREATE OR REPLACE TABLE gold_db.claims.fact_claims (
    claim_id        STRING        NOT NULL,
    patient_id      STRING        NOT NULL,
    provider_id     STRING,
    diagnosis_code  STRING        NOT NULL,
    claim_amount    NUMBER(12,2)  NOT NULL,
    claim_date      DATE          NOT NULL,
    status          STRING        DEFAULT 'SUBMITTED',
    ingested_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_claims PRIMARY KEY (claim_id),
    CONSTRAINT fk_claim_dx FOREIGN KEY (diagnosis_code)
        REFERENCES gold_db.reference.dim_diagnosis_codes(code_id)
);


-- =============================================================================
-- Sample data: ICD-10 circulatory subtree + claims
-- =============================================================================
--
-- Tree:
--   I00-I99 (chapter, level 1)
--     I20-I25 (block, level 2)
--       I25 (category, level 3)
--         I25.1 (subcategory, level 4)
--           I25.10 (billable, level 5)  <-- target of 2.2 traversal
--         I25.9 (billable, level 4)
--   J00-J99 (unrelated chapter sibling to prove descendants filter works)

INSERT INTO gold_db.reference.dim_diagnosis_codes
    (code_id, description, parent_code, code_level, is_billable, category)
VALUES
    ('I00-I99', 'Diseases of the circulatory system', NULL, 1, FALSE, 'CHAPTER'),
    ('I20-I25', 'Ischemic heart diseases',           'I00-I99', 2, FALSE, 'BLOCK'),
    ('I25',     'Chronic ischemic heart disease',    'I20-I25', 3, FALSE, 'CATEGORY'),
    ('I25.1',   'Atherosclerotic heart disease of native coronary artery', 'I25', 4, FALSE, 'SUBCATEGORY'),
    ('I25.10',  'Atherosclerotic heart disease of native coronary artery without angina pectoris',
                                                     'I25.1',   5, TRUE,  'DIAGNOSIS'),
    ('I25.9',   'Chronic ischemic heart disease, unspecified', 'I25', 4, TRUE, 'DIAGNOSIS'),
    ('J00-J99', 'Diseases of the respiratory system', NULL, 1, FALSE, 'CHAPTER');

INSERT INTO gold_db.claims.fact_claims
    (claim_id, patient_id, provider_id, diagnosis_code, claim_amount, claim_date, status)
VALUES
    ('CLM001', 'P001', 'PROV_A', 'I25.10', 4200.00, '2025-02-10', 'PAID'),
    ('CLM002', 'P002', 'PROV_A', 'I25.10', 3800.00, '2025-03-05', 'PAID'),
    ('CLM003', 'P003', 'PROV_B', 'I25.9',  2500.00, '2025-04-18', 'PAID'),
    ('CLM004', 'P004', 'PROV_C', 'I25.10', 5100.00, '2025-06-22', 'DENIED'),
    ('CLM005', 'P005', 'PROV_B', 'I25.9',  1900.00, '2025-08-30', 'PAID'),
    -- Unrelated respiratory claim (must NOT appear in I00-I99 rollup)
    ('CLM999', 'P999', 'PROV_Z', 'J00-J99', 999.00, '2025-09-01', 'PAID');


-- =============================================================================
-- 2.2 Traversing the Full Hierarchy (upward)
-- =============================================================================
--
-- Expected on the seed: one row, depth = 5, full_path from I00-I99 to I25.10.

WITH RECURSIVE code_path (
    code_id,
    description,
    parent_code,
    code_level,
    full_path,
    depth
) AS (
    -- Anchor: start at the specific diagnosis
    SELECT
        code_id,
        description,
        parent_code,
        code_level,
        code_id || ' - ' || description AS full_path,
        1 AS depth
    FROM gold_db.reference.dim_diagnosis_codes
    WHERE code_id = 'I25.10'

    UNION ALL

    -- Recursive member: walk up to parent
    SELECT
        parent.code_id,
        parent.description,
        parent.parent_code,
        parent.code_level,
        parent.code_id || ' - ' || parent.description || ' > ' || cp.full_path,
        cp.depth + 1
    FROM gold_db.reference.dim_diagnosis_codes parent
    JOIN code_path cp ON parent.code_id = cp.parent_code
)
SELECT full_path, depth
FROM code_path
WHERE parent_code IS NULL;


-- =============================================================================
-- 2.3 Aggregating Claims Across the Hierarchy (downward)
-- =============================================================================
--
-- Expected on the seed: one row — category='I00-I99', claim_count=5,
-- total_amount=17500.00. Excludes CLM999 (respiratory).

WITH RECURSIVE descendants (code_id) AS (
    SELECT code_id
    FROM gold_db.reference.dim_diagnosis_codes
    WHERE code_id = 'I00-I99'

    UNION ALL

    SELECT child.code_id
    FROM gold_db.reference.dim_diagnosis_codes child
    JOIN descendants d ON child.parent_code = d.code_id
)
SELECT
    'I00-I99'                  AS category,
    COUNT(DISTINCT c.claim_id) AS claim_count,
    SUM(c.claim_amount)        AS total_amount
FROM gold_db.claims.fact_claims c
JOIN descendants d ON c.diagnosis_code = d.code_id
WHERE c.claim_date >= '2025-01-01';

-- Depth-guarded variant (TR feedback, 2026-08): the recursive member carries a
-- level counter and stops once it passes the deepest legitimate level (7 for
-- ICD-10-CM). On a healthy hierarchy the result matches the unguarded query;
-- on corrupted data with a cycle it returns instead of running to the
-- statement timeout, and rows at the max level mark the branch to inspect.
WITH RECURSIVE descendants (code_id, lvl) AS (
    SELECT code_id, 1 AS lvl
    FROM gold_db.reference.dim_diagnosis_codes
    WHERE code_id = 'I00-I99'

    UNION ALL

    SELECT child.code_id, d.lvl + 1
    FROM gold_db.reference.dim_diagnosis_codes child
    JOIN descendants d ON child.parent_code = d.code_id
    WHERE d.lvl < 7
)
SELECT code_id, lvl FROM descendants;


-- =============================================================================
-- 2.4 Traversing Graph-Like Data with Shared Parents
-- =============================================================================
--
-- Bill of materials is a graph: a SKU can sit inside multiple kits and may
-- also be sold standalone. Two adjustments to the recursive pattern handle
-- the graph case:
--   1. Aggregation (SUM + GROUP BY) to avoid double-counting shared children.
--   2. A visited-nodes array to stop on cycles.

CREATE OR REPLACE TABLE silver_db.reference.bill_of_materials (
    parent_sku    STRING NOT NULL,
    child_sku     STRING NOT NULL,
    quantity      INT    NOT NULL,
    CONSTRAINT pk_bom PRIMARY KEY (parent_sku, child_sku)
);

-- Sample data. Graph shape:
--   KIT-ALPHA
--     |- SUB-ASSY-1 (qty 1) -> BRACKET (qty 4), SCREW (qty 8)
--     |- SUB-ASSY-2 (qty 1) -> BRACKET (qty 2), HINGE (qty 2)
--     |- LABEL      (qty 1)
-- BRACKET appears under TWO sub-assemblies. Expected expansion totals:
--   BRACKET 6, SCREW 8, HINGE 2, LABEL 1, SUB-ASSY-1 1, SUB-ASSY-2 1.

INSERT INTO silver_db.reference.bill_of_materials (parent_sku, child_sku, quantity)
VALUES
    ('KIT-ALPHA',  'SUB-ASSY-1', 1),
    ('KIT-ALPHA',  'SUB-ASSY-2', 1),
    ('KIT-ALPHA',  'LABEL',      1),
    ('SUB-ASSY-1', 'BRACKET',    4),
    ('SUB-ASSY-1', 'SCREW',      8),
    ('SUB-ASSY-2', 'BRACKET',    2),
    ('SUB-ASSY-2', 'HINGE',      2);

-- Expand a kit into total component requirements (graph-aware aggregation).
WITH RECURSIVE expanded_bom (
    parent_sku,
    child_sku,
    quantity
) AS (
    SELECT
        parent_sku,
        child_sku,
        quantity
    FROM silver_db.reference.bill_of_materials
    WHERE parent_sku = 'KIT-ALPHA'

    UNION ALL

    SELECT
        eb.parent_sku,
        bom.child_sku,
        eb.quantity * bom.quantity
    FROM silver_db.reference.bill_of_materials bom
    JOIN expanded_bom eb ON bom.parent_sku = eb.child_sku
)
SELECT
    child_sku,
    SUM(quantity) AS total_quantity
FROM expanded_bom
GROUP BY child_sku
ORDER BY total_quantity DESC;

-- Cycle-safe traversal: tracks visited parents in an array and stops the
-- recursion when the next child would close a cycle. Logging cycle-stop rows
-- is more useful than letting the query fail; cycles almost always indicate
-- an upstream data-quality bug.
WITH RECURSIVE traverse (
    parent_sku,
    child_sku,
    visited
) AS (
    SELECT
        parent_sku,
        child_sku,
        ARRAY_CONSTRUCT(parent_sku) AS visited
    FROM silver_db.reference.bill_of_materials
    WHERE parent_sku = 'KIT-ALPHA'

    UNION ALL

    SELECT
        bom.parent_sku,
        bom.child_sku,
        ARRAY_APPEND(t.visited, bom.parent_sku)
    FROM silver_db.reference.bill_of_materials bom
    JOIN traverse t ON bom.parent_sku = t.child_sku
    WHERE NOT ARRAY_CONTAINS(bom.child_sku::VARIANT, t.visited)
)
SELECT * FROM traverse;
