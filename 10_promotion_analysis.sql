-- ============================================================
-- 10_promotion_analysis.sql
-- SQL Retail Analytics — Promotion Analysis
-- ============================================================
-- Business Objective:
--   Quantify the incremental effect of each promotional lever
--   (Feature, Display, TPR, and combinations) on units sold,
--   revenue, and basket metrics. SQL translation of ML notebook
--   Chapters 10 (Promotion Analysis) and 11 (Promo Effectiveness).
--
-- Business Questions:
--   Which promo type (Feature / Display / TPR / Combined)
--   delivers the highest unit lift?
--   Does promotion effectiveness differ by category or segment?
--   What is the approximate promotional ROI?
--
-- SQL Concepts Demonstrated:
--   CASE WHEN, CTEs, window functions, LEFT JOIN, GROUP BY,
--   correlated subquery, conditional aggregation, PIVOT-style
-- ============================================================


-- ============================================================
-- PRM1: Promotion Type Distribution & Revenue Impact
-- ============================================================
-- Business Insight: Combined promotions (Feature + Display + TPR)
--   move the highest volume but may erode margin more than
--   single-lever tactics.

SELECT
    dp.category,
    f.promo_type,
    COUNT(*)                                        AS row_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY dp.category), 2) AS pct_of_category,
    SUM(f.units)                                    AS total_units,
    ROUND(AVG(f.units), 2)                          AS avg_units_per_row,
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    ROUND(AVG(f.spend), 4)                          AS avg_revenue_per_row,
    ROUND(AVG(f.price), 4)                          AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                   AS avg_discount_pct,
    ROUND(AVG(f.revenue_per_visit), 4)              AS avg_basket_value
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category, f.promo_type
ORDER BY dp.category, avg_units_per_row DESC;


-- ============================================================
-- PRM2: Promotion Lift vs Baseline (Units)
-- ============================================================
-- Business Insight: Key metric in the notebook Chapter 10.
--   "Lift" = incremental units driven by promotion.
--   Computed as: (avg units in promo weeks) / (avg units in baseline weeks) - 1

WITH baseline_stats AS (
    SELECT
        f.upc,
        AVG(f.units)                    AS baseline_avg_units,
        AVG(f.spend)                    AS baseline_avg_revenue,
        AVG(f.price)                    AS baseline_avg_price
    FROM marts.fact_sales f
    WHERE f.promo_type = 'NONE'
    GROUP BY f.upc
),
promo_stats AS (
    SELECT
        f.upc,
        f.promo_type,
        AVG(f.units)                    AS promo_avg_units,
        AVG(f.spend)                    AS promo_avg_revenue,
        AVG(f.price)                    AS promo_avg_price,
        COUNT(*)                        AS promo_row_count
    FROM marts.fact_sales f
    WHERE f.promo_type != 'NONE'
    GROUP BY f.upc, f.promo_type
)
SELECT
    dp.category,
    dp.description,
    ps.promo_type,
    ROUND(bs.baseline_avg_units, 2)     AS baseline_avg_units,
    ROUND(ps.promo_avg_units, 2)        AS promo_avg_units,
    ROUND(
        (ps.promo_avg_units - bs.baseline_avg_units)
        / NULLIF(bs.baseline_avg_units, 0) * 100, 2
    )                                   AS units_lift_pct,
    ROUND(bs.baseline_avg_price, 4)     AS baseline_avg_price,
    ROUND(ps.promo_avg_price, 4)        AS promo_avg_price,
    ROUND(
        (bs.baseline_avg_price - ps.promo_avg_price)
        / NULLIF(bs.baseline_avg_price, 0) * 100, 2
    )                                   AS price_reduction_pct,
    -- Revenue lift (might be negative if price cut is too deep)
    ROUND(
        (ps.promo_avg_revenue - bs.baseline_avg_revenue)
        / NULLIF(bs.baseline_avg_revenue, 0) * 100, 2
    )                                   AS revenue_lift_pct,
    ps.promo_row_count
FROM promo_stats ps
INNER JOIN baseline_stats bs ON bs.upc = ps.upc
INNER JOIN marts.dim_product dp ON dp.upc = ps.upc
ORDER BY dp.category, units_lift_pct DESC;


-- ============================================================
-- PRM3: Feature vs Display vs TPR — Individual Effect Comparison
-- ============================================================
-- Business Insight: "What is the impact on units/visit of each
--   promo type?" (Direct question from dunnhumby guide.)
--   Isolated comparison: one lever at a time.

SELECT
    dp.category,
    -- Baseline: No promotion
    ROUND(AVG(CASE WHEN f.promo_type = 'NONE'         THEN f.units END), 2) AS baseline_units,
    ROUND(AVG(CASE WHEN f.promo_type = 'FEATURE_ONLY' THEN f.units END), 2) AS feature_only_units,
    ROUND(AVG(CASE WHEN f.promo_type = 'DISPLAY_ONLY' THEN f.units END), 2) AS display_only_units,
    ROUND(AVG(CASE WHEN f.promo_type = 'TPR_ONLY'     THEN f.units END), 2) AS tpr_only_units,
    ROUND(AVG(CASE WHEN f.promo_type = 'COMBINED'     THEN f.units END), 2) AS combined_units,
    -- Lift multiples (vs baseline)
    ROUND(
        AVG(CASE WHEN f.promo_type = 'FEATURE_ONLY' THEN f.units END)
        / NULLIF(AVG(CASE WHEN f.promo_type = 'NONE' THEN f.units END), 0), 2
    )                                                               AS feature_lift_multiple,
    ROUND(
        AVG(CASE WHEN f.promo_type = 'DISPLAY_ONLY' THEN f.units END)
        / NULLIF(AVG(CASE WHEN f.promo_type = 'NONE' THEN f.units END), 0), 2
    )                                                               AS display_lift_multiple,
    ROUND(
        AVG(CASE WHEN f.promo_type = 'TPR_ONLY' THEN f.units END)
        / NULLIF(AVG(CASE WHEN f.promo_type = 'NONE' THEN f.units END), 0), 2
    )                                                               AS tpr_lift_multiple,
    ROUND(
        AVG(CASE WHEN f.promo_type = 'COMBINED' THEN f.units END)
        / NULLIF(AVG(CASE WHEN f.promo_type = 'NONE' THEN f.units END), 0), 2
    )                                                               AS combined_lift_multiple
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category
ORDER BY dp.category;


-- ============================================================
-- PRM4: Promo Lift by Store Segment
-- ============================================================
-- Business Insight: Does promotion respond differently in
--   Upscale vs Value stores? Value stores may have higher
--   baseline promo sensitivity.

SELECT
    ds.seg_value_name,
    dp.category,
    ROUND(AVG(CASE WHEN f.promo_type = 'NONE'     THEN f.units END), 2) AS baseline_units,
    ROUND(AVG(CASE WHEN f.is_promoted             THEN f.units END), 2) AS promoted_units,
    ROUND(
        AVG(CASE WHEN f.is_promoted THEN f.units END)
        / NULLIF(AVG(CASE WHEN f.promo_type = 'NONE' THEN f.units END), 0) - 1, 4
    ) * 100                                                             AS units_lift_pct,
    ROUND(AVG(CASE WHEN f.promo_type = 'NONE'     THEN f.price END), 4) AS baseline_price,
    ROUND(AVG(CASE WHEN f.is_promoted             THEN f.price END), 4) AS promo_price
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.seg_value_name, dp.category
ORDER BY dp.category, ds.seg_value_name;


-- ============================================================
-- PRM5: Promotional Frequency by Product
-- ============================================================
-- Business Insight: Products promoted >40% of weeks may be
--   "training" consumers to wait for deals — this erodes
--   base price perception and long-term brand equity.

SELECT
    dp.description,
    dp.category,
    dp.manufacturer,
    COUNT(*)                                AS total_rows,
    SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) AS promoted_rows,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                       AS promo_rate_pct,
    -- Breakdown by type
    SUM(CASE WHEN f.feature  = 1 THEN 1 ELSE 0 END) AS feature_weeks,
    SUM(CASE WHEN f.display  = 1 THEN 1 ELSE 0 END) AS display_weeks,
    SUM(CASE WHEN f.tpr_only = 1 THEN 1 ELSE 0 END) AS tpr_only_weeks,
    SUM(CASE WHEN f.promo_type = 'COMBINED' THEN 1 ELSE 0 END) AS combined_weeks,
    -- Revenue under promotion vs baseline
    ROUND(SUM(CASE WHEN f.is_promoted THEN f.spend ELSE 0 END), 2) AS promo_revenue,
    ROUND(SUM(CASE WHEN NOT f.is_promoted THEN f.spend ELSE 0 END), 2) AS baseline_revenue,
    -- Flag: high promo dependency
    CASE
        WHEN SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*) > 40
        THEN '⚠️ HIGH PROMO DEPENDENCY'
        ELSE '✓ HEALTHY'
    END                                     AS promo_health
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.description, dp.category, dp.manufacturer
ORDER BY promo_rate_pct DESC;


-- ============================================================
-- PRM6: Promotional ROI Approximation
-- ============================================================
-- Business Insight: Revenue generated during promo weeks vs
--   the discount cost (revenue foregone vs base price).
--   Positive ROI means promotion drives enough incremental
--   volume to offset the price cut.
--
--   Promo Revenue = actual spend in promo weeks
--   Foregone Revenue = (base_price - price) * units (promo weeks)
--   Net Revenue Impact = promo_revenue - foregone_revenue vs baseline

WITH by_promo_type AS (
    SELECT
        dp.category,
        f.promo_type,
        SUM(f.units)                                AS promo_units,
        ROUND(SUM(f.spend), 4)                      AS promo_revenue,
        -- Revenue foregone = discount × units
        ROUND(SUM(f.price_gap * f.units), 4)        AS revenue_foregone,
        -- Effective revenue = actual revenue - cost of discount
        ROUND(SUM(f.spend) - SUM(f.price_gap * f.units), 4) AS net_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    WHERE f.promo_type != 'NONE'
    GROUP BY dp.category, f.promo_type
)
SELECT
    category,
    promo_type,
    promo_units,
    promo_revenue,
    revenue_foregone,
    net_revenue,
    ROUND(revenue_foregone / NULLIF(promo_revenue, 0) * 100, 2) AS cost_as_pct_of_revenue,
    ROUND(net_revenue / NULLIF(promo_revenue, 0) * 100, 2)      AS net_margin_pct
FROM by_promo_type
ORDER BY category, net_margin_pct DESC;


-- ============================================================
-- PRM7: Week-over-Week Promo Calendar Heatmap (By Category)
-- ============================================================
-- Business Insight: When are promotions running? Detects
--   promotional stacking (multiple categories on promo same week)
--   which can dilute focus and hurt category management.

SELECT
    dc.week_end_date,
    dc.year,
    dc.quarter,
    dc.month_name,
    dc.is_holiday_season,
    -- Promo flag by category
    MAX(CASE WHEN dp.category = 'BAG SNACKS'            AND f.is_promoted THEN 1 ELSE 0 END) AS snacks_promo,
    MAX(CASE WHEN dp.category = 'COLD CEREAL'           AND f.is_promoted THEN 1 ELSE 0 END) AS cereal_promo,
    MAX(CASE WHEN dp.category = 'FROZEN PIZZA'          AND f.is_promoted THEN 1 ELSE 0 END) AS pizza_promo,
    MAX(CASE WHEN dp.category = 'ORAL HYGIENE PRODUCTS' AND f.is_promoted THEN 1 ELSE 0 END) AS oral_promo,
    -- Count of categories on promo
    COUNT(DISTINCT CASE WHEN f.is_promoted THEN dp.category END) AS categories_on_promo,
    -- Total promo rows
    SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END)  AS promo_rows,
    ROUND(SUM(f.spend), 2)                          AS total_revenue
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
GROUP BY dc.week_end_date, dc.year, dc.quarter, dc.month_name, dc.is_holiday_season
ORDER BY dc.week_end_date;

-- ============================================================
-- Business Recommendation:
--   1. Combined promotions (Feature + Display + TPR) produce
--      the highest unit lift but also the greatest margin risk.
--      Use selectively (max 4–6x/year per product).
--   2. Products with >40% promo weeks (PRM5) are in "promotion
--      trap" — consumers anchor on deal price. Detox strategy:
--      gradually reduce promo frequency over 3–6 months.
--   3. Avoid simultaneous promotions across all 4 categories
--      in the same week (PRM7) — dilutes promotional impact.
--
-- Interview Questions:
--   Q: What is "promotional lift" and how do you compute it in SQL?
--   A: Lift = (avg_units_promo / avg_units_baseline) - 1.
--      Compute baseline as avg units when promo_type = 'NONE',
--      then compare promoted periods using conditional AVG.
--
--   Q: What is "promotional dependency" and why is it harmful?
--   A: When >40% of a product's volume is sold on promotion,
--      consumers learn to wait for deals, eroding base price
--      perception and long-term brand equity.
-- ============================================================
