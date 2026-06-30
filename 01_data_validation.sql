-- ============================================================
-- 01_data_validation.sql
-- SQL Retail Analytics — Data Validation Suite
-- ============================================================
-- Business Objective:
--   Establish data quality baselines before any analysis.
--   Identify null values, impossible values, duplicate keys,
--   and statistical outliers that could corrupt downstream
--   business metrics.
--
-- Business Question:
--   Can we trust this dataset? What data quality issues
--   exist, and how prevalent are they?
--
-- SQL Concepts Demonstrated:
--   COUNT, SUM, CASE WHEN, subqueries, HAVING, GROUP BY,
--   IS NULL, BETWEEN, UNION ALL, COALESCE, NULLIF
--
-- Expected Output:
--   A set of validation reports, each flagging a specific
--   data quality dimension. Zero rows = clean; non-zero
--   rows = issues to remediate.
--
-- Performance Considerations:
--   Run against raw tables before any transformations.
--   Each check is independent and can be parallelized.
-- ============================================================


-- ============================================================
-- CHECK 1: Row Count Validation
-- ============================================================
-- Business Insight:
--   Verifies that ingestion loaded the expected volume.
--   Transaction: ~524,950 rows; Products: 58; Stores: 79.

SELECT
    'dh_transaction_data'   AS table_name,
    COUNT(*)                AS row_count,
    524950                  AS expected_rows,
    COUNT(*) - 524950       AS row_difference
FROM raw.dh_transaction_data

UNION ALL

SELECT
    'dh_product_lookup',
    COUNT(*),
    58,
    COUNT(*) - 58
FROM raw.dh_product_lookup

UNION ALL

SELECT
    'dh_store_lookup',
    COUNT(*),
    79,
    COUNT(*) - 79
FROM raw.dh_store_lookup;


-- ============================================================
-- CHECK 2: Null / Missing Value Audit — Transaction Table
-- ============================================================
-- Business Insight:
--   Null values in key metrics (spend, units, price) will
--   silently distort revenue and basket calculations.

SELECT
    'week_end_date'             AS column_name,
    COUNT(*) - COUNT(week_end_date) AS null_count,
    ROUND(
        (COUNT(*) - COUNT(week_end_date)) * 100.0 / COUNT(*), 4
    )                           AS null_pct
FROM raw.dh_transaction_data

UNION ALL SELECT 'store_num',   COUNT(*) - COUNT(store_num),   ROUND((COUNT(*) - COUNT(store_num))   * 100.0 / COUNT(*), 4) FROM raw.dh_transaction_data
UNION ALL SELECT 'upc',         COUNT(*) - COUNT(upc),         ROUND((COUNT(*) - COUNT(upc))         * 100.0 / COUNT(*), 4) FROM raw.dh_transaction_data
UNION ALL SELECT 'units',       COUNT(*) - COUNT(units),       ROUND((COUNT(*) - COUNT(units))       * 100.0 / COUNT(*), 4) FROM raw.dh_transaction_data
UNION ALL SELECT 'visits',      COUNT(*) - COUNT(visits),      ROUND((COUNT(*) - COUNT(visits))      * 100.0 / COUNT(*), 4) FROM raw.dh_transaction_data
UNION ALL SELECT 'hhs',         COUNT(*) - COUNT(hhs),         ROUND((COUNT(*) - COUNT(hhs))         * 100.0 / COUNT(*), 4) FROM raw.dh_transaction_data
UNION ALL SELECT 'spend',       COUNT(*) - COUNT(spend),       ROUND((COUNT(*) - COUNT(spend))       * 100.0 / COUNT(*), 4) FROM raw.dh_transaction_data
UNION ALL SELECT 'price',       COUNT(*) - COUNT(price),       ROUND((COUNT(*) - COUNT(price))       * 100.0 / COUNT(*), 4) FROM raw.dh_transaction_data
UNION ALL SELECT 'base_price',  COUNT(*) - COUNT(base_price),  ROUND((COUNT(*) - COUNT(base_price))  * 100.0 / COUNT(*), 4) FROM raw.dh_transaction_data

ORDER BY null_count DESC;


-- ============================================================
-- CHECK 3: Null Values — Store Lookup (PARKING_SPACE_QTY known null)
-- ============================================================
-- Business Insight:
--   Store 4503 (ROCKWALL) has null parking. This won't affect
--   revenue analysis but will affect store footprint modeling.

SELECT
    store_num,
    store_name,
    CASE WHEN parking_space_qty IS NULL THEN 'NULL' ELSE 'OK' END   AS parking_status,
    CASE WHEN sales_area_size_num IS NULL THEN 'NULL' ELSE 'OK' END AS area_status,
    CASE WHEN avg_weekly_baskets IS NULL THEN 'NULL' ELSE 'OK' END  AS baskets_status
FROM raw.dh_store_lookup
WHERE
    parking_space_qty IS NULL
    OR sales_area_size_num IS NULL
    OR avg_weekly_baskets IS NULL
ORDER BY store_num;


-- ============================================================
-- CHECK 4: Duplicate Primary Key Audit
-- ============================================================
-- Business Insight:
--   Duplicate store IDs (4503, 17627) have conflicting
--   SEG_VALUE_NAME (MAINSTREAM vs UPSCALE). This is a critical
--   data quality defect: dimension table cardinality must be 1:1.

-- Transaction duplicates (should be 0)
SELECT
    week_end_date,
    store_num,
    upc,
    COUNT(*)    AS occurrence_count
FROM raw.dh_transaction_data
GROUP BY week_end_date, store_num, upc
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC;


-- Store lookup duplicates
SELECT
    store_num,
    COUNT(*)        AS occurrence_count,
    -- Show the conflicting segment values
    STRING_AGG(DISTINCT seg_value_name, ' | ' ORDER BY seg_value_name) AS conflicting_segments
FROM raw.dh_store_lookup
GROUP BY store_num
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC;


-- Product lookup duplicates (should be 0)
SELECT
    upc,
    COUNT(*)    AS occurrence_count
FROM raw.dh_product_lookup
GROUP BY upc
HAVING COUNT(*) > 1;


-- ============================================================
-- CHECK 5: Referential Integrity — Orphan Transactions
-- ============================================================
-- Business Insight:
--   Transactions with no matching product or store record
--   cannot be enriched with dimensional attributes and must
--   be excluded or flagged.

-- Transactions with no matching product
SELECT
    'Missing Product'   AS issue_type,
    COUNT(*)            AS orphan_count
FROM raw.dh_transaction_data t
LEFT JOIN raw.dh_product_lookup p ON t.upc = p.upc
WHERE p.upc IS NULL

UNION ALL

-- Transactions with no matching store
SELECT
    'Missing Store',
    COUNT(*)
FROM raw.dh_transaction_data t
LEFT JOIN raw.dh_store_lookup s ON t.store_num = s.store_num
WHERE s.store_num IS NULL;


-- ============================================================
-- CHECK 6: Impossible Value Checks — Business Rules
-- ============================================================
-- Business Insight:
--   Values violating business rules (negative units, zero price,
--   price > $15) are almost certainly data entry or extraction errors.

SELECT
    'Negative Units'        AS issue,
    COUNT(*)                AS record_count
FROM raw.dh_transaction_data WHERE units < 0

UNION ALL SELECT 'Zero or Negative Price',    COUNT(*) FROM raw.dh_transaction_data WHERE price <= 0
UNION ALL SELECT 'Zero or Negative Spend (units>0)', COUNT(*) FROM raw.dh_transaction_data WHERE spend <= 0 AND units > 0
UNION ALL SELECT 'Price > Base Price',        COUNT(*) FROM raw.dh_transaction_data WHERE price > base_price + 0.01
UNION ALL SELECT 'Negative Base Price',       COUNT(*) FROM raw.dh_transaction_data WHERE base_price <= 0
UNION ALL SELECT 'Feature Not 0 or 1',        COUNT(*) FROM raw.dh_transaction_data WHERE feature NOT IN (0, 1)
UNION ALL SELECT 'Display Not 0 or 1',        COUNT(*) FROM raw.dh_transaction_data WHERE display NOT IN (0, 1)
UNION ALL SELECT 'TPR Not 0 or 1',            COUNT(*) FROM raw.dh_transaction_data WHERE tpr_only NOT IN (0, 1)
UNION ALL SELECT 'HHS > Visits',              COUNT(*) FROM raw.dh_transaction_data WHERE hhs > visits + 5
UNION ALL SELECT 'Visits > Units * 5',        COUNT(*) FROM raw.dh_transaction_data WHERE visits > units * 5 AND units > 0

ORDER BY record_count DESC;


-- ============================================================
-- CHECK 7: Outlier Detection — Units per Visit
-- ============================================================
-- Business Insight:
--   From the dunnhumby User Guide and the ML notebook:
--   "13 units/visit on a 15oz bag of pretzels" is an outlier.
--   Flag records where units/visit > 10 for review.

SELECT
    t.week_end_date,
    t.store_num,
    t.upc,
    p.description,
    p.category,
    t.units,
    t.visits,
    ROUND(t.units * 1.0 / NULLIF(t.visits, 0), 2)  AS units_per_visit,
    t.spend,
    t.price
FROM raw.dh_transaction_data t
LEFT JOIN raw.dh_product_lookup p ON t.upc = p.upc
WHERE
    t.visits > 0
    AND t.units * 1.0 / t.visits > 10
ORDER BY units_per_visit DESC
LIMIT 50;


-- ============================================================
-- CHECK 8: Outlier Detection — Visits per Household
-- ============================================================
-- Business Insight:
--   "9 visits in a single week by a household" is flagged
--   in the dunnhumby guide as a suspicious outlier.

SELECT
    t.week_end_date,
    t.store_num,
    t.upc,
    p.description,
    t.visits,
    t.hhs,
    ROUND(t.visits * 1.0 / NULLIF(t.hhs, 0), 2)    AS visits_per_hh,
    t.units
FROM raw.dh_transaction_data t
LEFT JOIN raw.dh_product_lookup p ON t.upc = p.upc
WHERE
    t.hhs > 0
    AND t.visits * 1.0 / t.hhs > 5
ORDER BY visits_per_hh DESC
LIMIT 50;


-- ============================================================
-- CHECK 9: Date Range & Continuity
-- ============================================================
-- Business Insight:
--   Confirms 156 complete weekly periods with no gaps.
--   Missing weeks would break time series analyses.

SELECT
    MIN(week_end_date)          AS first_week,
    MAX(week_end_date)          AS last_week,
    COUNT(DISTINCT week_end_date) AS distinct_weeks,
    156                         AS expected_weeks,
    COUNT(DISTINCT week_end_date) - 156 AS week_difference
FROM raw.dh_transaction_data;


-- CHECK 9b: Any gaps between consecutive weeks?
WITH weekly_dates AS (
    SELECT DISTINCT
        week_end_date,
        LAG(week_end_date) OVER (ORDER BY week_end_date) AS prev_week
    FROM raw.dh_transaction_data
)
SELECT
    prev_week               AS gap_after_week,
    week_end_date           AS next_week,
    -- PostgreSQL: week_end_date - prev_week
    -- Snowflake: DATEDIFF('day', prev_week, week_end_date)
    DATEDIFF('day', prev_week, week_end_date) AS days_between
FROM weekly_dates
WHERE
    prev_week IS NOT NULL
    AND DATEDIFF('day', prev_week, week_end_date) <> 7
ORDER BY gap_after_week;


-- ============================================================
-- CHECK 10: Summary Data Quality Scorecard
-- ============================================================
-- Business Insight:
--   A single-row summary of overall data quality health.
--   Suitable for automated monitoring / data contract alerts.

WITH quality_checks AS (
    SELECT
        COUNT(*)                                                        AS total_rows,
        SUM(CASE WHEN spend IS NULL THEN 1 ELSE 0 END)                AS null_spend,
        SUM(CASE WHEN price IS NULL OR price <= 0 THEN 1 ELSE 0 END)  AS bad_price,
        SUM(CASE WHEN spend <= 0 AND units > 0 THEN 1 ELSE 0 END)     AS zero_spend_with_units,
        SUM(CASE WHEN units < 0 THEN 1 ELSE 0 END)                    AS negative_units,
        SUM(
            CASE WHEN visits > 0 AND units * 1.0 / visits > 10
            THEN 1 ELSE 0 END
        )                                                               AS uv_outliers,
        SUM(
            CASE WHEN hhs > 0 AND visits * 1.0 / hhs > 5
            THEN 1 ELSE 0 END
        )                                                               AS vh_outliers
    FROM raw.dh_transaction_data
)
SELECT
    total_rows,
    null_spend,
    bad_price,
    zero_spend_with_units,
    negative_units,
    uv_outliers,
    vh_outliers,
    -- Total issues
    null_spend + bad_price + zero_spend_with_units + negative_units AS total_critical_issues,
    ROUND(
        (null_spend + bad_price + zero_spend_with_units + negative_units)
        * 100.0 / total_rows, 4
    ) AS issue_rate_pct,
    -- Quality grade
    CASE
        WHEN (null_spend + bad_price + zero_spend_with_units + negative_units) * 100.0 / total_rows < 0.1
            THEN 'PASS (< 0.1% issues)'
        WHEN (null_spend + bad_price + zero_spend_with_units + negative_units) * 100.0 / total_rows < 0.5
            THEN 'WARN (< 0.5% issues)'
        ELSE 'FAIL (>= 0.5% issues)'
    END AS quality_grade
FROM quality_checks;

-- ============================================================
-- Interview Questions This Query Answers:
--   Q: How do you validate a new dataset before analysis?
--   A: Systematic checks: nulls, duplicates, referential integrity,
--      range violations, outlier detection, temporal continuity.
--
--   Q: What is a data contract?
--   A: Formal agreement on expected schema, row counts, null rates,
--      and value ranges — enforced by automated validation queries.
--
-- Follow-up Analysis:
--   Build a dbt test layer that auto-runs these checks on
--   every pipeline execution and alerts on failure.
-- ============================================================
