-- ============================================================
-- 05_business_metrics.sql
-- SQL Retail Analytics — Core Business Metrics
-- ============================================================
-- Business Objective:
--   Compute the fundamental KPIs that any retail analytics
--   team tracks: revenue, volume, basket metrics, and
--   promotional effectiveness rates.
--
-- Business Questions:
--   What is total portfolio revenue? What is the average
--   basket value? How do metrics compare across segments?
--
-- SQL Concepts Demonstrated:
--   SUM, AVG, COUNT DISTINCT, CASE WHEN, NULLIF,
--   ROUND, window functions, subqueries, COALESCE
-- ============================================================


-- ============================================================
-- M1: Portfolio-Level KPIs (Single Executive Summary Row)
-- ============================================================
-- Business Insight: The entire 156-week dataset at a glance.
--   Avg basket value ~$3.74, avg discount ~5.7% — modest
--   overall, but promotional weeks show much deeper cuts.

SELECT
    -- Revenue
    ROUND(SUM(f.spend), 2)                                          AS total_revenue,
    ROUND(SUM(f.spend) / 1000000.0, 3)                             AS total_revenue_mm,

    -- Volume
    SUM(f.units)                                                    AS total_units,
    SUM(f.visits)                                                   AS total_visits,
    SUM(f.hhs)                                                      AS total_hhs,

    -- Basket Metrics (from ML notebook Chapter 3.2)
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)              AS avg_basket_value,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.visits), 0), 4)       AS avg_basket_size,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)                 AS avg_revenue_per_hh,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.hhs), 0), 4)          AS avg_units_per_hh,

    -- Pricing
    ROUND(AVG(f.price), 4)                                          AS avg_selling_price,
    ROUND(AVG(f.base_price), 4)                                     AS avg_base_price,
    ROUND(AVG(f.discount_pct), 4)                                   AS avg_discount_pct,

    -- Promotional Rates
    ROUND(
        SUM(CASE WHEN f.is_promoted   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS promo_rate_pct,
    ROUND(
        SUM(CASE WHEN f.feature = 1   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS feature_rate_pct,
    ROUND(
        SUM(CASE WHEN f.display = 1   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS display_rate_pct,
    ROUND(
        SUM(CASE WHEN f.tpr_only = 1  THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS tpr_rate_pct,
    ROUND(
        SUM(CASE WHEN f.promo_type = 'COMBINED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS combined_promo_rate_pct,

    -- Dataset dimensions
    COUNT(*)                                                        AS total_rows,
    COUNT(DISTINCT f.date_key)                                      AS total_weeks,
    COUNT(DISTINCT f.store_num)                                     AS total_stores,
    COUNT(DISTINCT f.upc)                                           AS total_products,
    COUNT(DISTINCT dp.category)                                     AS total_categories
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc;


-- ============================================================
-- M2: KPIs by Category
-- ============================================================
-- Business Insight: Cold Cereal typically leads in volume;
--   Oral Hygiene in price per unit. Compare to notebook EDA.

SELECT
    dp.category,

    -- Revenue
    ROUND(SUM(f.spend), 2)                                          AS total_revenue,
    ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2)    AS revenue_share_pct,

    -- Volume
    SUM(f.units)                                                    AS total_units,
    SUM(f.visits)                                                   AS total_visits,
    SUM(f.hhs)                                                      AS total_hhs,

    -- Basket & Pricing
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)              AS avg_basket_value,
    ROUND(AVG(f.price), 4)                                          AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                                   AS avg_discount_pct,

    -- Promo
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS promo_rate_pct,

    -- Rankings
    RANK() OVER (ORDER BY SUM(f.spend) DESC)                        AS revenue_rank,
    RANK() OVER (ORDER BY SUM(f.units) DESC)                        AS units_rank
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category
ORDER BY total_revenue DESC;


-- ============================================================
-- M3: KPIs by Store Segment
-- ============================================================
-- Business Insight: Upscale stores have higher basket value;
--   Value stores have higher promo sensitivity. Aligned with
--   notebook Chapter 2 EDA and Chapter 13 clustering results.

SELECT
    ds.seg_value_name,
    COUNT(DISTINCT ds.store_num)                                    AS store_count,
    ROUND(SUM(f.spend), 2)                                          AS total_revenue,
    ROUND(SUM(f.spend) / COUNT(DISTINCT ds.store_num), 2)          AS revenue_per_store,
    ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2)    AS revenue_share_pct,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)              AS avg_basket_value,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.visits), 0), 4)       AS avg_basket_size,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)                 AS avg_revenue_per_hh,
    ROUND(AVG(f.price), 4)                                          AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                                   AS avg_discount_pct,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS promo_rate_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.seg_value_name
ORDER BY total_revenue DESC;


-- ============================================================
-- M4: KPIs by State (Geographic Analysis)
-- ============================================================
-- Business Question: Which states drive the most revenue?
--   Are there regional pricing or promotional differences?

SELECT
    ds.state,
    COUNT(DISTINCT ds.store_num)                                    AS store_count,
    ROUND(SUM(f.spend), 2)                                          AS total_revenue,
    ROUND(SUM(f.spend) / COUNT(DISTINCT ds.store_num), 2)          AS revenue_per_store,
    ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2)    AS revenue_share_pct,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)              AS avg_basket_value,
    ROUND(AVG(f.price), 4)                                          AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                                   AS avg_discount_pct,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS promo_rate_pct,
    RANK() OVER (ORDER BY SUM(f.spend) DESC)                        AS revenue_rank
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.state
ORDER BY total_revenue DESC;


-- ============================================================
-- M5: KPIs by Manufacturer
-- ============================================================
-- Business Question: Which manufacturer dominates the portfolio?

SELECT
    dp.manufacturer,
    COUNT(DISTINCT dp.upc)                                          AS product_count,
    COUNT(DISTINCT dp.category)                                     AS categories_present,
    ROUND(SUM(f.spend), 2)                                          AS total_revenue,
    ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2)    AS revenue_share_pct,
    SUM(f.units)                                                    AS total_units,
    ROUND(AVG(f.price), 4)                                          AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                                   AS avg_discount_pct,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                               AS promo_rate_pct,
    RANK() OVER (ORDER BY SUM(f.spend) DESC)                        AS revenue_rank
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.manufacturer
ORDER BY total_revenue DESC;


-- ============================================================
-- M6: Basket Metrics Deep Dive
-- ============================================================
-- Business Insight: Basket metrics from ML notebook Chapter 3.2.
--   revenue_per_visit avg ~$3.74, units_per_hh avg ~1.14.
--   These are the foundation for customer behavior analysis.

SELECT
    dp.category,
    ds.seg_value_name,

    -- Units per Household (purchase intensity)
    ROUND(AVG(f.units_per_hh), 4)       AS avg_units_per_hh,
    ROUND(MAX(f.units_per_hh), 4)       AS max_units_per_hh,

    -- Revenue per Visit (basket value)
    ROUND(AVG(f.revenue_per_visit), 4)  AS avg_revenue_per_visit,
    ROUND(MAX(f.revenue_per_visit), 4)  AS max_revenue_per_visit,

    -- Spend per Household (loyalty value)
    ROUND(AVG(f.spend_per_hh), 4)       AS avg_spend_per_hh,

    -- HH to Visit ratio (revisit frequency)
    ROUND(
        SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0), 4
    )                                   AS avg_visits_per_hh
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
WHERE f.visits > 0 AND f.hhs > 0
GROUP BY dp.category, ds.seg_value_name
ORDER BY dp.category, ds.seg_value_name;


-- ============================================================
-- M7: Promoted vs Non-Promoted Metrics Side-by-Side
-- ============================================================
-- Business Insight: Direct comparison of KPIs in promotional
--   vs baseline weeks. This is the SQL equivalent of the
--   notebook's Chapter 10 promotion lift analysis setup.

SELECT
    dp.category,
    CASE WHEN f.is_promoted THEN 'PROMOTED' ELSE 'BASELINE' END AS period_type,

    COUNT(*)                                                    AS row_count,
    ROUND(SUM(f.spend), 2)                                      AS total_revenue,
    SUM(f.units)                                                AS total_units,
    ROUND(AVG(f.units), 2)                                      AS avg_units_per_row,
    ROUND(AVG(f.price), 4)                                      AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                               AS avg_discount_pct,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)          AS avg_basket_value
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category, CASE WHEN f.is_promoted THEN 'PROMOTED' ELSE 'BASELINE' END
ORDER BY dp.category, period_type;


-- ============================================================
-- M8: Revenue per Square Foot by Store Segment
-- ============================================================
-- Business Insight: Efficiency metric — revenue generated per
--   square foot of retail space. Upscale stores tend to be
--   more revenue-dense even if smaller.

SELECT
    ds.seg_value_name,
    ds.store_size_band,
    COUNT(DISTINCT ds.store_num)                                AS store_count,
    ROUND(SUM(f.spend), 2)                                      AS total_revenue,
    ROUND(AVG(ds.sales_area_size_num), 0)                       AS avg_sqft,
    ROUND(
        SUM(f.spend) / NULLIF(SUM(ds.sales_area_size_num), 0), 6
    )                                                           AS revenue_per_sqft,
    ROUND(AVG(ds.avg_weekly_baskets), 0)                        AS avg_weekly_baskets
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
WHERE ds.sales_area_size_num > 0
GROUP BY ds.seg_value_name, ds.store_size_band
ORDER BY revenue_per_sqft DESC;

-- ============================================================
-- Business Recommendation:
--   1. Upscale segment delivers highest basket value →
--      prioritize new product launches in Upscale stores first.
--   2. Avg discount of 5.7% suggests most weeks are non-promo;
--      targeted deep-discount campaigns could drive incremental volume.
--   3. Compare manufacturer revenue share to negotiate trade terms.
--
-- Interview Questions:
--   Q: What is "basket value" and why does it matter?
--   A: Basket value = revenue per transaction. It measures how
--      much a customer spends each time they buy. Higher basket
--      value = higher average order value (AOV). Retailers grow
--      it through upselling, display placement, and bundles.
--
--   Q: How do you compute revenue per square foot in SQL?
--   A: JOIN the fact table to store dimension for sqft, then
--      SUM(spend) / NULLIF(SUM(sales_area_size_num), 0).
--      Use NULLIF to avoid division-by-zero.
-- ============================================================
