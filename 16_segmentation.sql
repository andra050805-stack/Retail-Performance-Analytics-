-- ============================================================
-- 16_segmentation.sql
-- SQL Retail Analytics — Segmentation Analysis
-- ============================================================
-- Business Objective:
--   Segment products, stores, and customer behaviors into
--   actionable groups for targeted strategy. SQL implementation
--   of the clustering & segmentation chapter from the ML
--   notebook (Chapter 13 + 16). SQL segments support the
--   downstream K-Means / DBSCAN models.
--
-- Business Questions:
--   Which products belong to the same strategic group?
--   How do store characteristics cluster by revenue/basket?
--   What is the ABC × promotional dependency matrix?
--
-- SQL Concepts Demonstrated:
--   CASE WHEN (rule-based segmentation), NTILE, CROSS JOIN,
--   CTEs, multi-attribute classification, conditional aggregation
-- ============================================================


-- ============================================================
-- SG1: Product Strategic Matrix (ABC × Promo Dependency)
-- ============================================================
-- Business Insight: 9-cell strategic matrix — the core tool
--   from the ML notebook Chapter 13 (product clustering).
--   Cells drive different commercial strategies:
--   A + Low Promo = Premium Core (protect margin)
--   A + High Promo = Promotional Hero (manage dependency)
--   C + High Promo = Promotional Drain (review/exit)

WITH product_classified AS (
    SELECT
        dp.upc,
        dp.description,
        dp.category,
        dp.manufacturer,
        ROUND(SUM(f.spend), 4)              AS total_revenue,
        ROUND(AVG(f.discount_pct), 2)       AS avg_discount_pct,
        ROUND(
            SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
        )                                   AS promo_rate_pct,
        -- ABC via cumulative revenue
        CASE
            WHEN SUM(SUM(f.spend)) OVER (
                ORDER BY SUM(f.spend) DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) / SUM(SUM(f.spend)) OVER () <= 0.70 THEN 'A'
            WHEN SUM(SUM(f.spend)) OVER (
                ORDER BY SUM(f.spend) DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) / SUM(SUM(f.spend)) OVER () <= 0.90 THEN 'B'
            ELSE 'C'
        END AS abc_class
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.upc, dp.description, dp.category, dp.manufacturer
)
SELECT
    upc,
    description,
    category,
    manufacturer,
    ROUND(total_revenue, 2)         AS total_revenue,
    avg_discount_pct,
    promo_rate_pct,
    abc_class,

    -- Promo dependency tier
    CASE
        WHEN promo_rate_pct < 15  THEN 'LOW PROMO'
        WHEN promo_rate_pct < 35  THEN 'MEDIUM PROMO'
        ELSE                           'HIGH PROMO'
    END                             AS promo_dependency,

    -- 9-cell strategic matrix label
    CASE
        WHEN abc_class = 'A' AND promo_rate_pct < 15  THEN '🟢 Premium Core — Protect Margin'
        WHEN abc_class = 'A' AND promo_rate_pct < 35  THEN '🟡 Growth Hero — Moderate Promo'
        WHEN abc_class = 'A' AND promo_rate_pct >= 35 THEN '🟠 Promotional Hero — Manage Dependency'
        WHEN abc_class = 'B' AND promo_rate_pct < 15  THEN '🔵 Steady Earner — Maintain'
        WHEN abc_class = 'B' AND promo_rate_pct < 35  THEN '🔵 Active Secondary — Optimize'
        WHEN abc_class = 'B' AND promo_rate_pct >= 35 THEN '🟡 Promo-Dependent B — Watch'
        WHEN abc_class = 'C' AND promo_rate_pct < 15  THEN '⚪ Niche/Low-Volume — Review Range'
        WHEN abc_class = 'C' AND promo_rate_pct < 35  THEN '🔴 Low Value, Moderate Promo — Exit Candidate'
        ELSE                                                '🔴 Promotional Drain — Delisting Candidate'
    END                             AS strategic_cell
FROM product_classified
ORDER BY abc_class, promo_rate_pct DESC;


-- ============================================================
-- SG2: Store Segmentation Matrix (Revenue × Basket Value)
-- ============================================================
-- Business Insight: 4-quadrant store matrix:
--   High Revenue + High Basket = Star Stores → prioritize
--   High Revenue + Low Basket  = Volume Stores → upsell
--   Low Revenue  + High Basket = Premium Niche → expand
--   Low Revenue  + Low Basket  = Laggards → investigate

WITH store_metrics AS (
    SELECT
        f.store_num,
        ROUND(SUM(f.spend), 2) AS total_revenue,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value
    FROM marts.fact_sales f
    GROUP BY f.store_num
),
medians AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_revenue)    AS median_revenue,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_basket_value) AS median_basket
    FROM store_metrics
)
SELECT
    sm.store_num,
    ds.store_name,
    ds.state,
    ds.seg_value_name,
    sm.total_revenue,
    sm.avg_basket_value,
    ROUND(m.median_revenue, 2)  AS median_revenue,
    ROUND(m.median_basket, 4)   AS median_basket_value,

    -- 4-quadrant classification
    CASE
        WHEN sm.total_revenue >= m.median_revenue
             AND sm.avg_basket_value >= m.median_basket THEN '⭐ STAR — High Revenue, High Basket'
        WHEN sm.total_revenue >= m.median_revenue
             AND sm.avg_basket_value <  m.median_basket THEN '🔼 VOLUME — High Revenue, Low Basket'
        WHEN sm.total_revenue <  m.median_revenue
             AND sm.avg_basket_value >= m.median_basket THEN '💎 PREMIUM NICHE — Low Revenue, High Basket'
        ELSE                                                  '⚠️ LAGGARD — Low Revenue, Low Basket'
    END AS store_quadrant,

    -- Distance from median (for ranking within quadrant)
    ROUND(
        SQRT(
            POWER((sm.total_revenue - m.median_revenue) / NULLIF(m.median_revenue, 0), 2)
            + POWER((sm.avg_basket_value - m.median_basket) / NULLIF(m.median_basket, 0), 2)
        ), 4
    ) AS distance_from_median
FROM store_metrics sm
CROSS JOIN medians m
INNER JOIN marts.dim_store ds ON ds.store_num = sm.store_num
ORDER BY store_quadrant, total_revenue DESC;


-- ============================================================
-- SG3: Category Lifecycle Segmentation
-- ============================================================
-- Business Insight: Is the category growing (Growth), stable
--   (Mature), or contracting (Decline)? Simple rule-based
--   classification based on revenue trend — SQL proxy for
--   more complex ML lifecycle models from notebook Chapter 13.

WITH category_yearly AS (
    SELECT
        dp.category,
        dc.year,
        ROUND(SUM(f.spend), 2) AS annual_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dp.category, dc.year
),
cat_growth AS (
    SELECT
        category,
        year,
        annual_revenue,
        LAG(annual_revenue) OVER (PARTITION BY category ORDER BY year) AS prior_year,
        ROUND(
            (annual_revenue - LAG(annual_revenue) OVER (PARTITION BY category ORDER BY year))
            / NULLIF(LAG(annual_revenue) OVER (PARTITION BY category ORDER BY year), 0) * 100, 2
        ) AS yoy_growth_pct
    FROM category_yearly
),
cat_avg_growth AS (
    SELECT
        category,
        ROUND(AVG(yoy_growth_pct), 2) AS avg_yoy_growth_pct,
        MIN(yoy_growth_pct)            AS min_yoy,
        MAX(yoy_growth_pct)            AS max_yoy
    FROM cat_growth
    WHERE yoy_growth_pct IS NOT NULL
    GROUP BY category
)
SELECT
    category,
    avg_yoy_growth_pct,
    min_yoy,
    max_yoy,
    CASE
        WHEN avg_yoy_growth_pct >  5 THEN '📈 GROWTH'
        WHEN avg_yoy_growth_pct >= -2 THEN '📊 MATURE'
        ELSE                              '📉 DECLINE'
    END AS lifecycle_stage,
    CASE
        WHEN avg_yoy_growth_pct >  5 THEN 'Invest in distribution and new SKUs'
        WHEN avg_yoy_growth_pct >= -2 THEN 'Optimize assortment and margin'
        ELSE                              'Range rationalization and exit review'
    END AS recommended_strategy
FROM cat_avg_growth
ORDER BY avg_yoy_growth_pct DESC;


-- ============================================================
-- SG4: Price Sensitivity Segmentation (High/Medium/Low)
-- ============================================================
-- Business Insight: Products grouped by how much their price
--   varies across the store estate. High variation = inconsistent
--   pricing = opportunity for price architecture clarity.

WITH price_variation AS (
    SELECT
        dp.upc,
        dp.description,
        dp.category,
        ROUND(AVG(f.price), 4)      AS avg_price,
        ROUND(MIN(f.price), 4)      AS min_price,
        ROUND(MAX(f.price), 4)      AS max_price,
        ROUND(STDDEV(f.price), 4)   AS price_stddev,
        -- Coefficient of variation
        ROUND(STDDEV(f.price) / NULLIF(AVG(f.price), 0) * 100, 2) AS price_cv_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.upc, dp.description, dp.category
)
SELECT
    upc,
    description,
    category,
    avg_price,
    min_price,
    max_price,
    price_stddev,
    price_cv_pct,
    -- Price consistency segmentation
    CASE
        WHEN price_cv_pct < 5  THEN 'LOW VARIATION — Consistent pricing'
        WHEN price_cv_pct < 15 THEN 'MEDIUM VARIATION — Some inconsistency'
        ELSE                        'HIGH VARIATION — Pricing review needed'
    END AS price_consistency,
    -- Price tier
    CASE
        WHEN avg_price < 2.00 THEN 'Budget'
        WHEN avg_price < 4.00 THEN 'Mid-Tier'
        WHEN avg_price < 6.00 THEN 'Premium'
        ELSE                       'Super Premium'
    END AS price_tier
FROM price_variation
ORDER BY price_cv_pct DESC;


-- ============================================================
-- SG5: Customer Value Segmentation (Spend per HH Quartiles)
-- ============================================================
-- Business Insight: Group product-store combinations by
--   spend per household into 4 customer value tiers.
--   Approximates RFM (Recency-Frequency-Monetary) segmentation
--   at the product-store grain — aligned with notebook Chapter 13.

WITH hh_spend AS (
    SELECT
        f.store_num,
        f.upc,
        dp.category,
        dp.description,
        ds.seg_value_name,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4) AS spend_per_hh,
        ROUND(SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0), 4) AS visits_per_hh,
        ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.hhs), 0), 4) AS units_per_hh
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
    WHERE f.hhs > 0
    GROUP BY f.store_num, f.upc, dp.category, dp.description, ds.seg_value_name
)
SELECT
    store_num,
    upc,
    description,
    category,
    seg_value_name,
    spend_per_hh,
    visits_per_hh,
    units_per_hh,
    NTILE(4) OVER (ORDER BY spend_per_hh DESC)  AS spend_quartile,
    CASE NTILE(4) OVER (ORDER BY spend_per_hh DESC)
        WHEN 1 THEN 'HIGH VALUE HH — Loyalty candidates'
        WHEN 2 THEN 'MID-HIGH VALUE HH — Upsell targets'
        WHEN 3 THEN 'MID-LOW VALUE HH — Activation needed'
        WHEN 4 THEN 'LOW VALUE HH — Lapsed or occasional buyers'
    END AS hh_value_segment
FROM hh_spend
ORDER BY spend_per_hh DESC;


-- ============================================================
-- SG6: Multi-Attribute Segment Summary (for ML input)
-- ============================================================
-- Business Insight: This query produces the pre-segmentation
--   feature table for K-Means clustering in the ML notebook.
--   Each product-store row has multiple normalized features
--   ready for clustering algorithms.

SELECT
    f.store_num,
    f.upc,
    dp.description,
    dp.category,
    ds.seg_value_name,
    ds.state,

    -- Revenue features
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    ROUND(AVG(f.spend), 4)                          AS avg_weekly_revenue,

    -- Volume features
    ROUND(AVG(f.units), 4)                          AS avg_weekly_units,
    ROUND(AVG(f.units_per_hh), 4)                   AS avg_units_per_hh,

    -- Pricing features
    ROUND(AVG(f.price), 4)                          AS avg_price,
    ROUND(AVG(f.discount_pct), 4)                   AS avg_discount_pct,
    ROUND(STDDEV(f.price), 4)                       AS price_stddev,

    -- Promotion features
    ROUND(AVG(CAST(f.feature AS FLOAT)), 4)         AS feature_rate,
    ROUND(AVG(CAST(f.display AS FLOAT)), 4)         AS display_rate,
    ROUND(AVG(CAST(f.tpr_only AS FLOAT)), 4)        AS tpr_rate,
    ROUND(AVG(CAST(f.is_promoted AS FLOAT)), 4)     AS overall_promo_rate,

    -- Basket features
    ROUND(AVG(f.revenue_per_visit), 4)              AS avg_basket_value,
    ROUND(AVG(f.spend_per_hh), 4)                   AS avg_spend_per_hh,
    ROUND(SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0), 4) AS avg_visits_per_hh

FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
WHERE f.hhs > 0
GROUP BY f.store_num, f.upc, dp.description, dp.category,
         ds.seg_value_name, ds.state
ORDER BY total_revenue DESC;

-- ============================================================
-- Interview Questions:
--   Q: How do you implement a 2x2 strategic matrix in SQL?
--   A: Compute the median of each dimension (using PERCENTILE_CONT
--      or a CTE with median logic), then CASE WHEN against those
--      medians. CROSS JOIN the medians CTE to the metrics CTE.
--
--   Q: What is rule-based segmentation vs ML-based clustering?
--   A: Rule-based (SQL): fast, interpretable, auditable, based on
--      business knowledge. ML-based: discovers patterns without
--      predefined rules, better for complex high-dimensional data.
--      In practice, SQL segments are used to validate ML clusters.
-- ============================================================
