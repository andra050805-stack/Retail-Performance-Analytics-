-- ============================================================
-- 02_data_cleaning.sql
-- SQL Retail Analytics — Data Cleaning & Staging
-- ============================================================
-- Business Objective:
--   Resolve all data quality issues identified in 01_data_validation.sql.
--   Produce clean, analytics-ready staging tables that preserve
--   business logic from the ML notebook (Chapter 1).
--
-- Business Question:
--   How do we handle zero-spend rows, duplicate store IDs,
--   and outlier transactions in a reproducible, documented way?
--
-- SQL Concepts Demonstrated:
--   INSERT INTO SELECT, CTEs, COALESCE, NULLIF, CASE WHEN,
--   ROW_NUMBER (deduplication), GREATEST/LEAST, correlated subquery
--
-- Cleaning Decisions (aligned with ML notebook Chapter 1):
--   1. Zero spend + units > 0  → impute spend = units * price
--   2. Zero price (1 row)      → use base_price as substitute
--   3. Duplicate store IDs     → keep MAINSTREAM (first alphabetically)
--   4. Outlier flags added     → rows retained with flag columns
--   5. Derived metrics         → discount_pct, promo_type, etc.
-- ============================================================


-- ============================================================
-- STEP 1: Clean & Deduplicate Store Lookup
-- ============================================================
-- Issue: Store IDs 4503 and 17627 appear twice with conflicting
--        seg_value_name (MAINSTREAM vs UPSCALE).
-- Decision: Take the first record per store_num, ordered by
--           seg_value_name alphabetically (MAINSTREAM < UPSCALE).
--           This preserves the more conservative segment assignment.

INSERT INTO staging.stg_stores (
    store_num, store_name, city, state, msa_code,
    seg_value_name, parking_space_qty, sales_area_size_num, avg_weekly_baskets
)
WITH ranked_stores AS (
    SELECT
        store_num,
        store_name,
        address_city_name                   AS city,
        address_state_prov_code             AS state,
        msa_code,
        seg_value_name,
        parking_space_qty,
        sales_area_size_num,
        avg_weekly_baskets,
        ROW_NUMBER() OVER (
            PARTITION BY store_num
            ORDER BY seg_value_name ASC   -- MAINSTREAM before UPSCALE alphabetically
        )                                   AS row_rank
    FROM raw.dh_store_lookup
)
SELECT
    store_num,
    store_name,
    city,
    state,
    msa_code,
    seg_value_name,
    parking_space_qty,
    sales_area_size_num,
    avg_weekly_baskets
FROM ranked_stores
WHERE row_rank = 1;

-- Verify: Should now have exactly 79 rows (not 81)
-- SELECT COUNT(*) FROM staging.stg_stores;


-- ============================================================
-- STEP 2: Clean Product Lookup (no duplicates, minor cleaning)
-- ============================================================

INSERT INTO staging.stg_products (
    upc, category, description, manufacturer, sub_category, product_size
)
SELECT
    upc,
    UPPER(TRIM(category))       AS category,
    TRIM(description)           AS description,
    UPPER(TRIM(manufacturer))   AS manufacturer,
    UPPER(TRIM(sub_category))   AS sub_category,
    TRIM(product_size)          AS product_size
FROM raw.dh_product_lookup;


-- ============================================================
-- STEP 3: Clean Transaction Data
-- ============================================================
-- Cleaning rules applied:
--   a) spend imputed where spend=0 but units>0
--   b) price substituted where price=0 → use base_price
--   c) Outlier flags added (not removed) per dunnhumby guide
--   d) Derived pricing & promo features computed here
--   e) promo_type classification per notebook Chapter 3.3

INSERT INTO staging.stg_transactions (
    week_end_date, store_num, upc,
    units, visits, hhs, spend, price, base_price,
    feature, display, tpr_only,
    is_zero_spend, is_zero_price, is_outlier_uv, is_outlier_vh
)
SELECT
    t.week_end_date,
    t.store_num,
    t.upc,

    -- Units: keep as-is (no negative values found in validation)
    COALESCE(t.units, 0)                                        AS units,
    COALESCE(t.visits, 0)                                       AS visits,
    COALESCE(t.hhs, 0)                                          AS hhs,

    -- Spend: impute when zero but units > 0
    CASE
        WHEN COALESCE(t.spend, 0) <= 0 AND COALESCE(t.units, 0) > 0
            THEN COALESCE(t.units, 0) *
                 NULLIF(COALESCE(t.price, t.base_price), 0)
        ELSE COALESCE(t.spend, 0)
    END                                                         AS spend,

    -- Price: substitute base_price when price = 0
    CASE
        WHEN COALESCE(t.price, 0) <= 0
            THEN COALESCE(t.base_price, 0)
        ELSE t.price
    END                                                         AS price,

    COALESCE(t.base_price, t.price)                             AS base_price,

    -- Promotion flags: ensure 0/1 only
    CASE WHEN t.feature = 1 THEN 1 ELSE 0 END                  AS feature,
    CASE WHEN t.display = 1 THEN 1 ELSE 0 END                  AS display,
    CASE WHEN t.tpr_only = 1 THEN 1 ELSE 0 END                 AS tpr_only,

    -- Quality flags (rows kept, flagged for downstream exclusion if needed)
    CASE WHEN COALESCE(t.spend, 0) <= 0 AND COALESCE(t.units, 0) > 0
         THEN TRUE ELSE FALSE END                               AS is_zero_spend,
    CASE WHEN COALESCE(t.price, 0) <= 0
         THEN TRUE ELSE FALSE END                               AS is_zero_price,
    -- Units per visit outlier: > 10
    CASE WHEN COALESCE(t.visits, 0) > 0
              AND COALESCE(t.units, 0) * 1.0 / t.visits > 10
         THEN TRUE ELSE FALSE END                               AS is_outlier_uv,
    -- Visits per household outlier: > 5
    CASE WHEN COALESCE(t.hhs, 0) > 0
              AND COALESCE(t.visits, 0) * 1.0 / t.hhs > 5
         THEN TRUE ELSE FALSE END                               AS is_outlier_vh

FROM raw.dh_transaction_data t
-- Only include transactions with a matching store AND product
WHERE EXISTS (
    SELECT 1 FROM raw.dh_product_lookup p WHERE p.upc = t.upc
)
AND EXISTS (
    SELECT 1 FROM raw.dh_store_lookup s WHERE s.store_num = t.store_num
);


-- ============================================================
-- STEP 4: Populate dim_calendar
-- ============================================================
-- Generate a full date spine from first to last week.
-- Uses a recursive CTE to generate all 156 dates.

INSERT INTO marts.dim_calendar (
    date_key, week_end_date, year, quarter, month,
    month_name, week_num, week_of_year, is_holiday_season
)
WITH RECURSIVE date_spine AS (
    -- Anchor: first week in dataset
    SELECT MIN(week_end_date) AS week_end_date
    FROM staging.stg_transactions

    UNION ALL

    -- Recurse: add 7 days each step
    SELECT CAST(week_end_date + INTERVAL '7 days' AS DATE)
    FROM date_spine
    WHERE week_end_date < (SELECT MAX(week_end_date) FROM staging.stg_transactions)
),
calendar_enriched AS (
    SELECT
        week_end_date,
        CAST(TO_CHAR(week_end_date, 'YYYYMMDD') AS INTEGER)    AS date_key,
        EXTRACT(YEAR FROM week_end_date)::INTEGER               AS year,
        EXTRACT(QUARTER FROM week_end_date)::INTEGER            AS quarter,
        EXTRACT(MONTH FROM week_end_date)::INTEGER              AS month,
        TO_CHAR(week_end_date, 'Month')                         AS month_name,
        EXTRACT(WEEK FROM week_end_date)::INTEGER               AS week_num,
        ROW_NUMBER() OVER (ORDER BY week_end_date)::INTEGER     AS week_of_year
    FROM date_spine
)
SELECT
    date_key,
    week_end_date,
    year,
    quarter,
    month,
    TRIM(month_name)    AS month_name,
    week_num,
    week_of_year,
    -- Flag Nov–Dec as holiday season (high promotional activity)
    CASE WHEN month IN (11, 12) THEN TRUE ELSE FALSE END AS is_holiday_season
FROM calendar_enriched;


-- ============================================================
-- STEP 5: Populate dim_product
-- ============================================================

INSERT INTO marts.dim_product (
    upc, description, category, sub_category, manufacturer,
    product_size, category_code
)
SELECT
    upc,
    description,
    category,
    sub_category,
    manufacturer,
    product_size,
    -- Short category code for display
    CASE category
        WHEN 'BAG SNACKS'           THEN 'SNCK'
        WHEN 'COLD CEREAL'          THEN 'CERL'
        WHEN 'FROZEN PIZZA'         THEN 'PZZA'
        WHEN 'ORAL HYGIENE PRODUCTS' THEN 'ORAL'
        ELSE 'OTHR'
    END AS category_code
FROM staging.stg_products;


-- ============================================================
-- STEP 6: Populate dim_store
-- ============================================================

INSERT INTO marts.dim_store (
    store_num, store_name, city, state, msa_code, seg_value_name,
    parking_space_qty, sales_area_size_num, avg_weekly_baskets,
    store_size_band, parking_band
)
SELECT
    store_num,
    store_name,
    city,
    state,
    msa_code,
    seg_value_name,
    parking_space_qty,
    sales_area_size_num,
    avg_weekly_baskets,
    -- Store size band (sq ft)
    CASE
        WHEN sales_area_size_num < 40000  THEN 'Small'
        WHEN sales_area_size_num < 60000  THEN 'Medium'
        ELSE                                   'Large'
    END AS store_size_band,
    -- Parking band
    CASE
        WHEN parking_space_qty IS NULL         THEN 'Unknown'
        WHEN parking_space_qty < 300           THEN 'Low'
        WHEN parking_space_qty < 500           THEN 'Medium'
        ELSE                                        'High'
    END AS parking_band
FROM staging.stg_stores;


-- ============================================================
-- STEP 7: Populate fact_sales (Central Fact Table)
-- ============================================================

INSERT INTO marts.fact_sales (
    date_key, store_num, upc,
    units, visits, hhs, spend, price, base_price,
    feature, display, tpr_only,
    discount_pct, price_gap, revenue_per_visit,
    units_per_hh, spend_per_hh, promo_type, is_promoted
)
SELECT
    -- Keys
    CAST(TO_CHAR(t.week_end_date, 'YYYYMMDD') AS INTEGER)      AS date_key,
    t.store_num,
    t.upc,

    -- Core measures
    t.units,
    t.visits,
    t.hhs,
    t.spend,
    t.price,
    t.base_price,
    t.feature,
    t.display,
    t.tpr_only,

    -- Derived pricing features (Chapter 3.1 of ML notebook)
    CASE
        WHEN t.base_price > 0
            THEN ROUND((t.base_price - t.price) / t.base_price * 100, 4)
        ELSE 0
    END                                                         AS discount_pct,

    ROUND(t.base_price - t.price, 4)                            AS price_gap,

    -- Derived sales features (Chapter 3.2 of ML notebook)
    CASE
        WHEN t.visits > 0 THEN ROUND(t.spend / t.visits, 4)
        ELSE NULL
    END                                                         AS revenue_per_visit,

    CASE
        WHEN t.hhs > 0 THEN ROUND(t.units * 1.0 / t.hhs, 4)
        ELSE NULL
    END                                                         AS units_per_hh,

    CASE
        WHEN t.hhs > 0 THEN ROUND(t.spend / t.hhs, 4)
        ELSE NULL
    END                                                         AS spend_per_hh,

    -- Promotion type classification (Chapter 3.3 logic)
    CASE
        WHEN t.feature = 1 AND t.display = 1 AND t.tpr_only = 1 THEN 'COMBINED'
        WHEN t.feature = 1 AND t.display = 1                     THEN 'FEATURE_DISPLAY'
        WHEN t.feature = 1 AND t.tpr_only = 1                    THEN 'FEATURE_TPR'
        WHEN t.display = 1 AND t.tpr_only = 1                    THEN 'DISPLAY_TPR'
        WHEN t.feature = 1                                        THEN 'FEATURE_ONLY'
        WHEN t.display = 1                                        THEN 'DISPLAY_ONLY'
        WHEN t.tpr_only = 1                                       THEN 'TPR_ONLY'
        ELSE                                                           'NONE'
    END                                                         AS promo_type,

    -- is_promoted: any promotional support
    CASE
        WHEN t.feature = 1 OR t.display = 1 OR t.tpr_only = 1
        THEN TRUE ELSE FALSE
    END                                                         AS is_promoted

FROM staging.stg_transactions t
-- Join to calendar to get date_key
INNER JOIN marts.dim_calendar c ON c.week_end_date = t.week_end_date
-- Only include records with valid store and product
INNER JOIN marts.dim_store s ON s.store_num = t.store_num
INNER JOIN marts.dim_product p ON p.upc = t.upc;


-- ============================================================
-- STEP 8: Cleaning Verification Report
-- ============================================================
-- Business Insight: Confirm cleaning produced expected results.

SELECT
    'fact_sales rows'           AS metric,
    CAST(COUNT(*) AS VARCHAR)   AS value
FROM marts.fact_sales

UNION ALL SELECT 'dim_product rows',   CAST(COUNT(*) AS VARCHAR) FROM marts.dim_product
UNION ALL SELECT 'dim_store rows',     CAST(COUNT(*) AS VARCHAR) FROM marts.dim_store
UNION ALL SELECT 'dim_calendar rows',  CAST(COUNT(*) AS VARCHAR) FROM marts.dim_calendar

UNION ALL SELECT
    'Rows with imputed spend',
    CAST(SUM(CASE WHEN is_promoted = FALSE AND spend != units * price THEN 1 ELSE 0 END) AS VARCHAR)
FROM marts.fact_sales

UNION ALL SELECT
    'Promoted rows',
    CAST(SUM(CASE WHEN is_promoted THEN 1 ELSE 0 END) AS VARCHAR)
FROM marts.fact_sales

UNION ALL SELECT
    'Avg discount %',
    CAST(ROUND(AVG(discount_pct), 2) AS VARCHAR)
FROM marts.fact_sales;

-- ============================================================
-- Interview Questions:
--   Q: What is the best way to handle zero-value spend records?
--   A: Impute using units × price when the price is valid.
--      Flag originals for auditability. Never silently drop.
--
--   Q: How do you handle duplicate dimension keys?
--   A: ROW_NUMBER() PARTITION BY key + business rule to pick
--      the canonical record. Document the rule explicitly.
--
-- Follow-up Analysis:
--   Add a data lineage table tracking how many rows were
--   modified in each cleaning step for audit trail.
-- ============================================================
