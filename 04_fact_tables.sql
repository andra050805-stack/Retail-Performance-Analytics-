-- ============================================================
-- 04_fact_tables.sql
-- SQL Retail Analytics — Fact Table Exploration & Aggregates
-- ============================================================
-- Business Objective:
--   Validate the central fact_sales table, populate aggregate
--   mart tables, and establish baseline business metrics from
--   the grain-level data.
--
-- Business Question:
--   What does the fact table look like at the grain level?
--   What pre-aggregated tables improve dashboard performance?
--
-- SQL Concepts Demonstrated:
--   INSERT INTO SELECT, GROUP BY with ROLLUP, HAVING,
--   CASE WHEN, window functions, correlated subquery,
--   multi-level aggregation, COALESCE
-- ============================================================


-- ============================================================
-- A. FACT TABLE PROFILE — Grain & Distribution
-- ============================================================

-- A1: Fact table statistical profile
SELECT
    COUNT(*)                            AS total_rows,
    COUNT(DISTINCT date_key)            AS distinct_weeks,
    COUNT(DISTINCT store_num)           AS distinct_stores,
    COUNT(DISTINCT upc)                 AS distinct_upcs,

    -- Revenue
    ROUND(SUM(spend), 2)                AS total_revenue,
    ROUND(AVG(spend), 4)                AS avg_spend_per_row,
    ROUND(MIN(spend), 4)                AS min_spend,
    ROUND(MAX(spend), 4)                AS max_spend,

    -- Volume
    SUM(units)                          AS total_units,
    ROUND(AVG(units), 2)                AS avg_units_per_row,

    -- Promotion
    SUM(CASE WHEN is_promoted THEN 1 ELSE 0 END)    AS promoted_rows,
    ROUND(
        SUM(CASE WHEN is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                   AS promo_rate_pct,

    -- Pricing
    ROUND(AVG(price), 4)                AS avg_price,
    ROUND(AVG(base_price), 4)           AS avg_base_price,
    ROUND(AVG(discount_pct), 4)         AS avg_discount_pct
FROM marts.fact_sales;


-- A2: Promotion type distribution (Chapter 3.3 of ML notebook)
SELECT
    promo_type,
    COUNT(*)                            AS row_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_rows,
    SUM(units)                          AS total_units,
    ROUND(SUM(spend), 2)                AS total_revenue,
    ROUND(AVG(units), 2)                AS avg_units_per_row,
    ROUND(AVG(spend), 4)                AS avg_revenue_per_row,
    ROUND(AVG(discount_pct), 2)         AS avg_discount_pct
FROM marts.fact_sales
GROUP BY promo_type
ORDER BY total_revenue DESC;


-- A3: Revenue distribution by category (top-level view)
SELECT
    dp.category,
    COUNT(*)                            AS row_count,
    SUM(f.units)                        AS total_units,
    ROUND(SUM(f.spend), 2)              AS total_revenue,
    ROUND(AVG(f.price), 4)              AS avg_price,
    ROUND(AVG(f.discount_pct), 2)       AS avg_discount_pct,
    ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2) AS revenue_share_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category
ORDER BY total_revenue DESC;


-- ============================================================
-- B. POPULATE AGGREGATE MART — agg_weekly_store_category
-- ============================================================
-- Purpose: Pre-aggregated weekly × store × category table.
--          Reduces query time for trend dashboards from
--          full 524K scan to ~50K aggregated rows.

INSERT INTO marts.agg_weekly_store_category (
    date_key, store_num, category,
    total_units, total_visits, total_hhs, total_spend,
    avg_price, avg_discount_pct, promo_weeks
)
SELECT
    f.date_key,
    f.store_num,
    dp.category,
    SUM(f.units)                        AS total_units,
    SUM(f.visits)                        AS total_visits,
    SUM(f.hhs)                           AS total_hhs,
    ROUND(SUM(f.spend), 4)               AS total_spend,
    ROUND(AVG(f.price), 4)               AS avg_price,
    ROUND(AVG(f.discount_pct), 4)        AS avg_discount_pct,
    -- Count of product-weeks with any promotion in this store-week
    SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) AS promo_weeks
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY f.date_key, f.store_num, dp.category;


-- ============================================================
-- C. POPULATE AGGREGATE MART — agg_product_summary
-- ============================================================

INSERT INTO marts.agg_product_summary (
    upc, description, category,
    total_revenue, total_units, total_visits,
    avg_price, avg_discount_pct, promo_weeks_pct,
    revenue_rank, abc_class
)
WITH product_totals AS (
    SELECT
        f.upc,
        dp.description,
        dp.category,
        ROUND(SUM(f.spend), 4)              AS total_revenue,
        SUM(f.units)                         AS total_units,
        SUM(f.visits)                        AS total_visits,
        ROUND(AVG(f.price), 4)               AS avg_price,
        ROUND(AVG(f.discount_pct), 4)        AS avg_discount_pct,
        ROUND(
            SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
        )                                    AS promo_weeks_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY f.upc, dp.description, dp.category
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY total_revenue DESC)   AS revenue_rank,
        SUM(total_revenue) OVER ()                  AS grand_total_revenue,
        SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                           AS cumulative_revenue
    FROM product_totals
)
SELECT
    upc,
    description,
    category,
    total_revenue,
    total_units,
    total_visits,
    avg_price,
    avg_discount_pct,
    promo_weeks_pct,
    revenue_rank,
    -- ABC Classification (aligned with Chapter 16 / segmentation)
    CASE
        WHEN cumulative_revenue / grand_total_revenue <= 0.70 THEN 'A'
        WHEN cumulative_revenue / grand_total_revenue <= 0.90 THEN 'B'
        ELSE                                                        'C'
    END AS abc_class
FROM ranked;


-- ============================================================
-- D. POPULATE AGGREGATE MART — agg_store_summary
-- ============================================================

INSERT INTO marts.agg_store_summary (
    store_num, store_name, seg_value_name, state,
    total_revenue, total_units, total_visits,
    avg_basket_value, revenue_per_sqft, revenue_rank
)
WITH store_totals AS (
    SELECT
        f.store_num,
        ds.store_name,
        ds.seg_value_name,
        ds.state,
        ds.sales_area_size_num,
        ROUND(SUM(f.spend), 4)              AS total_revenue,
        SUM(f.units)                         AS total_units,
        SUM(f.visits)                        AS total_visits,
        ROUND(
            SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4
        )                                    AS avg_basket_value
    FROM marts.fact_sales f
    INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
    GROUP BY f.store_num, ds.store_name, ds.seg_value_name, ds.state, ds.sales_area_size_num
)
SELECT
    store_num,
    store_name,
    seg_value_name,
    state,
    total_revenue,
    total_units,
    total_visits,
    avg_basket_value,
    ROUND(total_revenue / NULLIF(sales_area_size_num, 0), 6) AS revenue_per_sqft,
    RANK() OVER (ORDER BY total_revenue DESC)                AS revenue_rank
FROM store_totals;


-- ============================================================
-- E. ROLLUP — Revenue by Category, Sub-category, Product
-- ============================================================
-- Business Insight: Hierarchical revenue summary with subtotals.
--   ROLLUP generates automatic sub-totals at each level.
--   NULL in a GROUP BY column = that level's subtotal row.

SELECT
    COALESCE(dp.category, 'ALL CATEGORIES')        AS category,
    COALESCE(dp.sub_category, 'ALL SUB-CATEGORIES') AS sub_category,
    COALESCE(dp.description, 'ALL PRODUCTS')        AS product,
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    SUM(f.units)                                    AS total_units,
    COUNT(DISTINCT f.store_num)                     AS stores_selling
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY ROLLUP (dp.category, dp.sub_category, dp.description)
ORDER BY dp.category NULLS LAST, dp.sub_category NULLS LAST, total_revenue DESC;


-- ============================================================
-- F. HAVING — Find Categories With Avg Discount > 5%
-- ============================================================
-- Business Question: Which categories are most frequently discounted?
SELECT
    dp.category,
    ROUND(AVG(f.discount_pct), 2)       AS avg_discount_pct,
    COUNT(*)                            AS total_rows,
    SUM(CASE WHEN f.discount_pct > 0 THEN 1 ELSE 0 END) AS discounted_rows,
    ROUND(SUM(CASE WHEN f.discount_pct > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
                                        AS pct_rows_discounted
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category
HAVING AVG(f.discount_pct) > 5
ORDER BY avg_discount_pct DESC;


-- ============================================================
-- G. Fact Table Completeness Check (FULL OUTER JOIN)
-- ============================================================
-- Business Question: Are there any products or stores completely
--   absent from the fact table?

-- Products with zero transactions
SELECT
    dp.upc,
    dp.description,
    dp.category,
    'NO TRANSACTIONS' AS status
FROM marts.dim_product dp
LEFT JOIN marts.fact_sales f ON f.upc = dp.upc
WHERE f.upc IS NULL

UNION ALL

-- Stores with zero transactions
SELECT
    ds.store_num::BIGINT,
    ds.store_name,
    ds.seg_value_name,
    'NO TRANSACTIONS'
FROM marts.dim_store ds
LEFT JOIN marts.fact_sales f ON f.store_num = ds.store_num
WHERE f.store_num IS NULL;

-- ============================================================
-- Interview Questions:
--   Q: What is the difference between GROUP BY and GROUP BY ROLLUP?
--   A: ROLLUP generates subtotals at each level of the hierarchy,
--      inserting NULL for the grouping columns at subtotal rows.
--      Perfect for financial hierarchies and drill-down reports.
--
--   Q: When do you use aggregate mart tables vs querying the fact?
--   A: Aggregate marts pre-compute common aggregations, reducing
--      query time 10–100× for dashboard loads. Use fact table
--      for ad-hoc, drill-down, or row-level analysis.
--
-- Follow-up Analysis:
--   Build a CUBE aggregate over (category, state, year) to
--   support multi-dimensional pivot analysis without repeated
--   GROUP BY queries.
-- ============================================================
