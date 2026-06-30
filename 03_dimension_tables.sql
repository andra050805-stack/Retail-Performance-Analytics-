-- ============================================================
-- 03_dimension_tables.sql
-- SQL Retail Analytics — Dimension Table Queries
-- ============================================================
-- Business Objective:
--   Verify, explore, and document the three dimension tables
--   (dim_product, dim_store, dim_calendar). These are the
--   descriptive context that enriches every fact_sales query.
--
-- SQL Concepts Demonstrated:
--   SELECT, GROUP BY, COUNT, ORDER BY, CASE WHEN, CROSS JOIN,
--   SELF JOIN (implicit via GROUP BY), window functions
-- ============================================================


-- ============================================================
-- A. DIM_PRODUCT — Product Hierarchy Exploration
-- ============================================================

-- A1: Category summary
-- Business Question: What is the product mix?
SELECT
    p.category,
    COUNT(DISTINCT p.upc)           AS product_count,
    COUNT(DISTINCT p.manufacturer)  AS manufacturer_count,
    COUNT(DISTINCT p.sub_category)  AS sub_category_count,
    -- List manufacturers per category
    STRING_AGG(DISTINCT p.manufacturer, ', ' ORDER BY p.manufacturer) AS manufacturers
FROM marts.dim_product p
GROUP BY p.category
ORDER BY product_count DESC;


-- A2: Full product catalog with rankings
-- Business Question: What are all 58 products in the dataset?
SELECT
    ROW_NUMBER() OVER (ORDER BY p.category, p.manufacturer, p.description)
                            AS product_num,
    p.category,
    p.sub_category,
    p.manufacturer,
    p.description,
    p.product_size,
    p.upc
FROM marts.dim_product p
ORDER BY p.category, p.manufacturer, p.description;


-- A3: Products per sub-category
SELECT
    p.category,
    p.sub_category,
    COUNT(*)                AS product_count,
    STRING_AGG(p.description, ' | ' ORDER BY p.description) AS products
FROM marts.dim_product p
GROUP BY p.category, p.sub_category
ORDER BY p.category, product_count DESC;


-- ============================================================
-- B. DIM_STORE — Store Portfolio Analysis
-- ============================================================

-- B1: Store segment distribution
-- Business Question: How are stores distributed across value tiers?
SELECT
    seg_value_name,
    COUNT(*)                            AS store_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total,
    ROUND(AVG(sales_area_size_num), 0)  AS avg_sqft,
    ROUND(AVG(avg_weekly_baskets), 0)   AS avg_weekly_baskets,
    ROUND(AVG(parking_space_qty), 0)    AS avg_parking
FROM marts.dim_store
GROUP BY seg_value_name
ORDER BY store_count DESC;


-- B2: State distribution
-- Business Question: Which states have the most stores?
SELECT
    state,
    COUNT(*)                AS store_count,
    -- Segment breakdown per state
    SUM(CASE WHEN seg_value_name = 'UPSCALE'    THEN 1 ELSE 0 END) AS upscale_stores,
    SUM(CASE WHEN seg_value_name = 'MAINSTREAM' THEN 1 ELSE 0 END) AS mainstream_stores,
    SUM(CASE WHEN seg_value_name = 'VALUE'      THEN 1 ELSE 0 END) AS value_stores,
    STRING_AGG(DISTINCT msa_code::VARCHAR, ', ') AS msa_codes
FROM marts.dim_store
GROUP BY state
ORDER BY store_count DESC;


-- B3: Store size analysis
-- Business Question: How are stores distributed by physical size?
SELECT
    store_size_band,
    seg_value_name,
    COUNT(*)                            AS store_count,
    ROUND(AVG(sales_area_size_num), 0)  AS avg_sqft,
    MIN(sales_area_size_num)            AS min_sqft,
    MAX(sales_area_size_num)            AS max_sqft,
    ROUND(AVG(avg_weekly_baskets), 0)   AS avg_baskets
FROM marts.dim_store
GROUP BY store_size_band, seg_value_name
ORDER BY store_size_band, seg_value_name;


-- B4: Full store roster
SELECT
    store_num,
    store_name,
    city,
    state,
    seg_value_name,
    store_size_band,
    sales_area_size_num,
    COALESCE(CAST(parking_space_qty AS VARCHAR), 'N/A')     AS parking,
    ROUND(avg_weekly_baskets, 0)    AS avg_weekly_baskets
FROM marts.dim_store
ORDER BY state, seg_value_name, store_num;


-- B5: SELF JOIN — Stores in same MSA (metro market)
-- Business Question: Which stores compete in the same market?
-- Business Insight: Useful for localized pricing strategy.
SELECT
    s1.msa_code,
    s1.store_num                    AS store_a,
    s1.store_name                   AS store_a_name,
    s1.seg_value_name               AS store_a_segment,
    s2.store_num                    AS store_b,
    s2.store_name                   AS store_b_name,
    s2.seg_value_name               AS store_b_segment
FROM marts.dim_store s1
INNER JOIN marts.dim_store s2
    ON s1.msa_code = s2.msa_code
    AND s1.store_num < s2.store_num   -- avoid duplicate pairs
WHERE s1.msa_code IS NOT NULL
ORDER BY s1.msa_code, s1.store_num;


-- ============================================================
-- C. DIM_CALENDAR — Time Dimension Analysis
-- ============================================================

-- C1: Calendar overview
SELECT
    MIN(week_end_date)  AS first_week,
    MAX(week_end_date)  AS last_week,
    COUNT(*)            AS total_weeks,
    MIN(year)           AS first_year,
    MAX(year)           AS last_year,
    COUNT(DISTINCT year) AS num_years
FROM marts.dim_calendar;


-- C2: Weeks per year and quarter
SELECT
    year,
    quarter,
    COUNT(*) AS weeks_in_quarter,
    MIN(week_end_date) AS quarter_start,
    MAX(week_end_date) AS quarter_end
FROM marts.dim_calendar
GROUP BY year, quarter
ORDER BY year, quarter;


-- C3: Holiday season breakdown
SELECT
    is_holiday_season,
    COUNT(*)        AS week_count,
    MIN(week_end_date) AS first_week,
    MAX(week_end_date) AS last_week
FROM marts.dim_calendar
GROUP BY is_holiday_season;


-- ============================================================
-- D. CROSS JOIN — All Product × Store Combinations
-- ============================================================
-- Business Question: How many product-store combinations are possible?
-- Business Insight: Coverage analysis — are all stores selling all products?

SELECT
    COUNT(DISTINCT f.store_num || '-' || f.upc::VARCHAR) AS actual_combinations,
    (SELECT COUNT(DISTINCT store_num) FROM marts.dim_store) *
    (SELECT COUNT(DISTINCT upc) FROM marts.dim_product)   AS possible_combinations,
    ROUND(
        COUNT(DISTINCT f.store_num || '-' || f.upc::VARCHAR) * 100.0 /
        (
            (SELECT COUNT(DISTINCT store_num) FROM marts.dim_store) *
            (SELECT COUNT(DISTINCT upc) FROM marts.dim_product)
        ), 1
    ) AS coverage_pct
FROM marts.fact_sales f;


-- D2: Product coverage by store (which stores stock which categories)
SELECT
    ds.store_num,
    ds.store_name,
    ds.seg_value_name,
    COUNT(DISTINCT dp.category)     AS categories_carried,
    COUNT(DISTINCT f.upc)           AS unique_products_sold,
    58                              AS total_possible_products,
    ROUND(COUNT(DISTINCT f.upc) * 100.0 / 58, 1) AS product_coverage_pct
FROM marts.dim_store ds
LEFT JOIN marts.fact_sales f    ON f.store_num = ds.store_num
LEFT JOIN marts.dim_product dp  ON dp.upc = f.upc
GROUP BY ds.store_num, ds.store_name, ds.seg_value_name
ORDER BY product_coverage_pct DESC;

-- ============================================================
-- Interview Questions:
--   Q: Why use a surrogate key (date_key as INTEGER) instead
--      of the natural date?
--   A: INTEGER comparisons are faster than DATE. YYYYMMDD
--      format allows date range scans with simple arithmetic.
--      Also ensures compatibility across platforms (Snowflake,
--      BigQuery, PostgreSQL handle DATE types differently).
--
--   Q: When would you use a CROSS JOIN?
--   A: To generate all possible combinations (product × store
--      coverage analysis, date spine × product for zero-fill).
--
-- Follow-up Analysis:
--   Create a zero-fill fact table that inserts 0-unit rows
--   for all product-store-week combinations with no sales,
--   enabling accurate averages and trend analysis.
-- ============================================================
