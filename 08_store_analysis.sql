-- ============================================================
-- 08_store_analysis.sql
-- SQL Retail Analytics — Store Performance Analysis
-- ============================================================
-- Business Objective:
--   Rank all 79 stores by revenue, basket metrics, and
--   efficiency. Compare performance across store segments
--   (Upscale / Mainstream / Value), states, and size bands.
--   Aligned with ML notebook Chapter 8 (Store Analysis)
--   and Chapter 13 (Store Clustering).
--
-- Business Questions:
--   Which stores are the top performers and why?
--   Do Upscale stores generate higher basket value?
--   Which states have the most efficient store footprint?
--
-- SQL Concepts Demonstrated:
--   RANK, DENSE_RANK, NTILE, window functions, CTEs,
--   LEFT JOIN, COALESCE, CASE WHEN, correlated subquery
-- ============================================================


-- ============================================================
-- ST1: Full Store Revenue Ranking
-- ============================================================

SELECT
    RANK() OVER (ORDER BY SUM(f.spend) DESC)        AS revenue_rank,
    ds.store_num,
    ds.store_name,
    ds.city,
    ds.state,
    ds.seg_value_name,
    ds.store_size_band,
    ds.sales_area_size_num,

    -- Revenue & Volume
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    SUM(f.units)                                    AS total_units,
    SUM(f.visits)                                   AS total_visits,
    SUM(f.hhs)                                      AS total_hhs,

    -- Efficiency Metrics
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)  AS avg_basket_value,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_size,
    ROUND(SUM(f.spend) / NULLIF(ds.sales_area_size_num, 0), 6) AS revenue_per_sqft,

    -- Pricing
    ROUND(AVG(f.price), 4)                          AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                   AS avg_discount_pct,

    -- Promo Intensity
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                               AS promo_rate_pct

FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY
    ds.store_num, ds.store_name, ds.city, ds.state,
    ds.seg_value_name, ds.store_size_band, ds.sales_area_size_num
ORDER BY total_revenue DESC;


-- ============================================================
-- ST2: Store Segment Comparison — Upscale vs Mainstream vs Value
-- ============================================================
-- Business Insight: Key strategic question from notebook Chapter 8.
--   Upscale stores should show higher avg basket values and
--   lower promo dependency.

SELECT
    ds.seg_value_name,
    COUNT(DISTINCT ds.store_num)                    AS store_count,
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    ROUND(SUM(f.spend) / COUNT(DISTINCT ds.store_num), 2) AS revenue_per_store,
    ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2) AS revenue_share_pct,

    -- Basket
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_size,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)    AS avg_spend_per_hh,

    -- Pricing
    ROUND(AVG(f.price), 4)                          AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                   AS avg_discount_pct,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                               AS promo_rate_pct,

    -- Physical
    ROUND(AVG(ds.sales_area_size_num), 0)           AS avg_sqft,
    ROUND(AVG(ds.avg_weekly_baskets), 0)            AS avg_weekly_baskets,
    ROUND(SUM(f.spend) / NULLIF(SUM(ds.sales_area_size_num), 0), 6) AS revenue_per_sqft
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.seg_value_name
ORDER BY total_revenue DESC;


-- ============================================================
-- ST3: State-Level Store Performance
-- ============================================================
-- Business Question: Which geographic markets perform best?
--   Revenue density (per store) and basket value differ by state.

SELECT
    ds.state,
    COUNT(DISTINCT ds.store_num)                    AS store_count,
    -- Segment mix
    SUM(CASE WHEN ds.seg_value_name = 'UPSCALE'    THEN 1 ELSE 0 END) AS upscale,
    SUM(CASE WHEN ds.seg_value_name = 'MAINSTREAM' THEN 1 ELSE 0 END) AS mainstream,
    SUM(CASE WHEN ds.seg_value_name = 'VALUE'      THEN 1 ELSE 0 END) AS value_stores,
    -- Revenue
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    ROUND(SUM(f.spend) / COUNT(DISTINCT ds.store_num), 2) AS revenue_per_store,
    ROUND(
        SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2
    )                                               AS revenue_share_pct,
    -- Basket
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
    ROUND(AVG(f.discount_pct), 2)                   AS avg_discount_pct,
    RANK() OVER (ORDER BY SUM(f.spend) DESC)         AS state_revenue_rank
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.state
ORDER BY total_revenue DESC;


-- ============================================================
-- ST4: Top 10 and Bottom 10 Stores
-- ============================================================
-- Business Insight: Executive-friendly view of extremes.
--   Bottom stores need intervention: operational review,
--   price repositioning, or closure evaluation.

WITH store_ranked AS (
    SELECT
        ds.store_num,
        ds.store_name,
        ds.state,
        ds.seg_value_name,
        ds.sales_area_size_num,
        ROUND(SUM(f.spend), 2)      AS total_revenue,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
        ROUND(AVG(f.discount_pct), 2) AS avg_discount_pct,
        RANK() OVER (ORDER BY SUM(f.spend) DESC)  AS rank_top,
        RANK() OVER (ORDER BY SUM(f.spend) ASC)   AS rank_bottom
    FROM marts.fact_sales f
    INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
    GROUP BY ds.store_num, ds.store_name, ds.state,
             ds.seg_value_name, ds.sales_area_size_num
)
(
    SELECT 'TOP 10' AS group_label, rank_top AS rank, store_num, store_name,
           state, seg_value_name, sales_area_size_num,
           total_revenue, avg_basket_value, avg_discount_pct
    FROM store_ranked WHERE rank_top <= 10
    ORDER BY rank_top
)
UNION ALL
(
    SELECT 'BOTTOM 10', rank_bottom, store_num, store_name,
           state, seg_value_name, sales_area_size_num,
           total_revenue, avg_basket_value, avg_discount_pct
    FROM store_ranked WHERE rank_bottom <= 10
    ORDER BY rank_bottom
);


-- ============================================================
-- ST5: Store NTILE Quartile Grouping
-- ============================================================
-- Business Insight: Divide stores into performance quartiles
--   (NTILE=4) for targeted strategy assignment.
--   Q1 = top performers → invest; Q4 = laggards → review.

SELECT
    NTILE(4) OVER (ORDER BY SUM(f.spend) DESC)      AS revenue_quartile,
    ds.store_num,
    ds.store_name,
    ds.state,
    ds.seg_value_name,
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
    ROUND(AVG(f.discount_pct), 2)                   AS avg_discount_pct,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                               AS promo_rate_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.store_num, ds.store_name, ds.state, ds.seg_value_name
ORDER BY revenue_quartile, total_revenue DESC;


-- ============================================================
-- ST6: Revenue per Square Foot Ranking
-- ============================================================
-- Business Insight: Efficiency metric — most revenue per unit
--   of retail space. Critical for real estate decisions.
--   A small Upscale store might outperform a large Value store.

SELECT
    RANK() OVER (
        ORDER BY SUM(f.spend) / NULLIF(MAX(ds.sales_area_size_num), 0) DESC
    )                                               AS efficiency_rank,
    ds.store_num,
    ds.store_name,
    ds.state,
    ds.seg_value_name,
    ds.sales_area_size_num,
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    ROUND(
        SUM(f.spend) / NULLIF(MAX(ds.sales_area_size_num), 0), 6
    )                                               AS revenue_per_sqft,
    -- Compare to segment average (correlated subquery)
    ROUND(
        SUM(f.spend) / NULLIF(MAX(ds.sales_area_size_num), 0)
        - (
            SELECT SUM(f2.spend) / NULLIF(SUM(ds2.sales_area_size_num), 0)
            FROM marts.fact_sales f2
            INNER JOIN marts.dim_store ds2 ON ds2.store_num = f2.store_num
            WHERE ds2.seg_value_name = ds.seg_value_name
        ), 6
    )                                               AS vs_segment_avg_per_sqft
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
WHERE ds.sales_area_size_num > 0
GROUP BY ds.store_num, ds.store_name, ds.state,
         ds.seg_value_name, ds.sales_area_size_num
ORDER BY revenue_per_sqft DESC;


-- ============================================================
-- ST7: Store Category Mix — Which Categories Does Each Store Lead?
-- ============================================================
-- Business Insight: Some stores over-index on Cereal; others
--   on Frozen Pizza. Useful for targeted assortment planning.

WITH store_cat AS (
    SELECT
        f.store_num,
        dp.category,
        ROUND(SUM(f.spend), 2)      AS category_revenue,
        RANK() OVER (
            PARTITION BY f.store_num ORDER BY SUM(f.spend) DESC
        )                           AS cat_rank_within_store
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY f.store_num, dp.category
)
SELECT
    sc.store_num,
    ds.store_name,
    ds.seg_value_name,
    sc.category,
    sc.category_revenue,
    sc.cat_rank_within_store,
    CASE sc.cat_rank_within_store
        WHEN 1 THEN 'PRIMARY CATEGORY'
        WHEN 2 THEN 'SECONDARY'
        WHEN 3 THEN 'TERTIARY'
        ELSE        'TAIL'
    END                             AS category_role
FROM store_cat sc
INNER JOIN marts.dim_store ds ON ds.store_num = sc.store_num
WHERE sc.cat_rank_within_store = 1   -- Show only each store's #1 category
ORDER BY ds.seg_value_name, sc.category_revenue DESC;


-- ============================================================
-- ST8: Stores With Below-Average Basket Value (HAVING + Subquery)
-- ============================================================
-- Business Insight: Stores with basket value below the portfolio
--   average need targeted promotional or assortment intervention.

SELECT
    ds.store_num,
    ds.store_name,
    ds.state,
    ds.seg_value_name,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
    ROUND(
        (SELECT SUM(f2.spend) / NULLIF(SUM(f2.visits), 0) FROM marts.fact_sales f2), 4
    )                                                   AS portfolio_avg_basket,
    ROUND(
        SUM(f.spend) / NULLIF(SUM(f.visits), 0)
        - (SELECT SUM(f2.spend) / NULLIF(SUM(f2.visits), 0) FROM marts.fact_sales f2), 4
    )                                                   AS diff_vs_portfolio_avg
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.store_num, ds.store_name, ds.state, ds.seg_value_name
HAVING SUM(f.spend) / NULLIF(SUM(f.visits), 0)
    < (SELECT SUM(f2.spend) / NULLIF(SUM(f2.visits), 0) FROM marts.fact_sales f2)
ORDER BY avg_basket_value ASC;

-- ============================================================
-- Business Recommendation:
--   1. Q1 stores (ST5) receive first allocation of new product launches.
--   2. Bottom 10 stores (ST4) need root cause analysis —
--      check category mix, local competition, and promotional calendar.
--   3. Revenue per sqft (ST6) guides real estate renewal decisions.
--
-- Interview Questions:
--   Q: What is the difference between NTILE and RANK?
--   A: NTILE(n) divides rows into n equal-sized buckets.
--      RANK assigns a specific position to each row, with ties
--      receiving the same rank. NTILE is better for segmentation;
--      RANK is better for top-N leaderboards.
--
--   Q: How do you compare a row to an aggregated benchmark?
--   A: Use a scalar correlated subquery in the SELECT clause,
--      or pre-compute the benchmark in a CTE and JOIN to it.
-- ============================================================
