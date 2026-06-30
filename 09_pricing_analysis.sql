-- ============================================================
-- 09_pricing_analysis.sql
-- SQL Retail Analytics — Pricing Analysis
-- ============================================================
-- Business Objective:
--   Translate the ML notebook's pricing analysis (Chapters 3,
--   9, 10) into SQL. Analyze price distributions, discount
--   depths, price band effects on volume, and price elasticity
--   approximation without ML models.
--
-- Business Questions:
--   What price bands drive the most volume?
--   At what discount depth does volume respond materially?
--   Which products are most price-sensitive?
--   Are there price thresholds that unlock step-change demand?
--
-- SQL Concepts Demonstrated:
--   CASE WHEN (price banding), CTEs, window functions,
--   correlated subqueries, ROUND, NULLIF, percentile approx,
--   NTILE for quartile bands, GROUP BY + HAVING
-- ============================================================


-- ============================================================
-- PR1: Price Range Summary by Product
-- ============================================================
-- Business Insight: Every product's min, max, and average
--   shelf price across 156 weeks and 79 stores.

SELECT
    dp.description,
    dp.category,
    dp.manufacturer,
    dp.product_size,
    ROUND(MIN(f.price), 4)          AS min_price,
    ROUND(MAX(f.price), 4)          AS max_price,
    ROUND(AVG(f.price), 4)          AS avg_price,
    ROUND(AVG(f.base_price), 4)     AS avg_base_price,
    ROUND(MAX(f.price) - MIN(f.price), 4) AS price_range,
    ROUND(AVG(f.discount_pct), 2)   AS avg_discount_pct,
    ROUND(MAX(f.discount_pct), 2)   AS max_discount_pct,
    SUM(f.units)                    AS total_units,
    -- Price coefficient of variation (price volatility)
    ROUND(
        STDDEV(f.price) / NULLIF(AVG(f.price), 0) * 100, 2
    )                               AS price_cv_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.description, dp.category, dp.manufacturer, dp.product_size
ORDER BY dp.category, avg_price DESC;


-- ============================================================
-- PR2: Price Band Analysis — Volume by Price Bucket
-- ============================================================
-- Business Insight: Directly answers the dunnhumby guide's
--   question: "Are there specific price thresholds that, if
--   crossed, drive significant differences in sales?"
--   Based on notebook Chapter 9 price threshold analysis.

SELECT
    dp.category,
    -- Price bands: $0.50 buckets
    CASE
        WHEN f.price < 1.00  THEN 'Under $1.00'
        WHEN f.price < 1.50  THEN '$1.00 – $1.49'
        WHEN f.price < 2.00  THEN '$1.50 – $1.99'
        WHEN f.price < 2.50  THEN '$2.00 – $2.49'
        WHEN f.price < 3.00  THEN '$2.50 – $2.99'
        WHEN f.price < 3.50  THEN '$3.00 – $3.49'
        WHEN f.price < 4.00  THEN '$3.50 – $3.99'
        WHEN f.price < 5.00  THEN '$4.00 – $4.99'
        WHEN f.price < 6.00  THEN '$5.00 – $5.99'
        ELSE                      '$6.00+'
    END                             AS price_band,
    COUNT(*)                        AS row_count,
    SUM(f.units)                    AS total_units,
    ROUND(AVG(f.units), 2)          AS avg_units_per_row,
    ROUND(SUM(f.spend), 2)          AS total_revenue,
    ROUND(AVG(f.price), 4)          AS avg_price_in_band,
    ROUND(AVG(f.discount_pct), 2)   AS avg_discount_pct,
    -- Revenue share within category
    ROUND(
        SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (PARTITION BY dp.category), 2
    )                               AS pct_of_category_revenue
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category, CASE
    WHEN f.price < 1.00  THEN 'Under $1.00'
    WHEN f.price < 1.50  THEN '$1.00 – $1.49'
    WHEN f.price < 2.00  THEN '$1.50 – $1.99'
    WHEN f.price < 2.50  THEN '$2.00 – $2.49'
    WHEN f.price < 3.00  THEN '$2.50 – $2.99'
    WHEN f.price < 3.50  THEN '$3.00 – $3.49'
    WHEN f.price < 4.00  THEN '$3.50 – $3.99'
    WHEN f.price < 5.00  THEN '$4.00 – $4.99'
    WHEN f.price < 6.00  THEN '$5.00 – $5.99'
    ELSE                      '$6.00+'
END
ORDER BY dp.category, avg_price_in_band;


-- ============================================================
-- PR3: Discount Depth Distribution
-- ============================================================
-- Business Insight: Distribution of discount percentages.
--   Most weeks have 0% discount (no promo). Promotional weeks
--   cluster at 10–30% off. Deep discounts (>30%) are rare.
--   Aligned with notebook Chapter 3 discount feature analysis.

SELECT
    dp.category,
    -- Discount depth buckets
    CASE
        WHEN f.discount_pct = 0                 THEN '0% (No discount)'
        WHEN f.discount_pct BETWEEN 0.01 AND 5  THEN '0.1% – 5%'
        WHEN f.discount_pct BETWEEN 5.01 AND 10 THEN '5.1% – 10%'
        WHEN f.discount_pct BETWEEN 10.01 AND 15 THEN '10.1% – 15%'
        WHEN f.discount_pct BETWEEN 15.01 AND 20 THEN '15.1% – 20%'
        WHEN f.discount_pct BETWEEN 20.01 AND 30 THEN '20.1% – 30%'
        ELSE                                          '30%+ (Deep discount)'
    END                                         AS discount_bucket,
    COUNT(*)                                    AS row_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY dp.category), 2) AS pct_of_rows,
    SUM(f.units)                                AS total_units,
    ROUND(AVG(f.units), 2)                      AS avg_units_per_row,
    ROUND(AVG(f.discount_pct), 2)               AS avg_discount_in_bucket,
    ROUND(SUM(f.spend), 2)                      AS total_revenue
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category, CASE
    WHEN f.discount_pct = 0                 THEN '0% (No discount)'
    WHEN f.discount_pct BETWEEN 0.01 AND 5  THEN '0.1% – 5%'
    WHEN f.discount_pct BETWEEN 5.01 AND 10 THEN '5.1% – 10%'
    WHEN f.discount_pct BETWEEN 10.01 AND 15 THEN '10.1% – 15%'
    WHEN f.discount_pct BETWEEN 15.01 AND 20 THEN '15.1% – 20%'
    WHEN f.discount_pct BETWEEN 20.01 AND 30 THEN '20.1% – 30%'
    ELSE                                          '30%+ (Deep discount)'
END
ORDER BY dp.category, avg_discount_in_bucket;


-- ============================================================
-- PR4: Price Elasticity Approximation (SQL Proxy)
-- ============================================================
-- Business Insight: True elasticity requires regression, but
--   SQL can approximate it by comparing average units at high
--   vs low price quartiles within each product.
--   Formula: % change in units / % change in price
--   Elastic < -1 | Inelastic > -1
--   Aligned with notebook Chapter 9 elasticity section.

WITH price_quartile AS (
    SELECT
        f.upc,
        dp.description,
        dp.category,
        f.units,
        f.price,
        NTILE(4) OVER (
            PARTITION BY f.upc ORDER BY f.price ASC
        )                   AS price_quartile
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    WHERE f.units > 0
),
quartile_agg AS (
    SELECT
        upc,
        description,
        category,
        price_quartile,
        ROUND(AVG(units), 4) AS avg_units,
        ROUND(AVG(price), 4) AS avg_price
    FROM price_quartile
    GROUP BY upc, description, category, price_quartile
),
low_high AS (
    SELECT
        q1.upc,
        q1.description,
        q1.category,
        q1.avg_price    AS q1_avg_price,
        q1.avg_units    AS q1_avg_units,
        q4.avg_price    AS q4_avg_price,
        q4.avg_units    AS q4_avg_units
    FROM quartile_agg q1
    INNER JOIN quartile_agg q4
        ON q1.upc = q4.upc AND q1.price_quartile = 1 AND q4.price_quartile = 4
)
SELECT
    upc,
    description,
    category,
    ROUND(q1_avg_price, 4)  AS avg_low_price,
    ROUND(q4_avg_price, 4)  AS avg_high_price,
    ROUND(q1_avg_units, 2)  AS avg_units_at_low_price,
    ROUND(q4_avg_units, 2)  AS avg_units_at_high_price,
    -- % change in price (low → high)
    ROUND(
        (q4_avg_price - q1_avg_price) / NULLIF(q1_avg_price, 0) * 100, 2
    )                       AS pct_price_increase,
    -- % change in units (low → high)
    ROUND(
        (q4_avg_units - q1_avg_units) / NULLIF(q1_avg_units, 0) * 100, 2
    )                       AS pct_units_change,
    -- Price elasticity proxy
    ROUND(
        ((q4_avg_units - q1_avg_units) / NULLIF(q1_avg_units, 0))
        / NULLIF((q4_avg_price - q1_avg_price) / NULLIF(q1_avg_price, 0), 0), 4
    )                       AS price_elasticity_proxy,
    -- Classification
    CASE
        WHEN ABS(
            ((q4_avg_units - q1_avg_units) / NULLIF(q1_avg_units, 0))
            / NULLIF((q4_avg_price - q1_avg_price) / NULLIF(q1_avg_price, 0), 0)
        ) > 1 THEN 'ELASTIC (price sensitive)'
        ELSE       'INELASTIC (price insensitive)'
    END                     AS elasticity_class
FROM low_high
ORDER BY ABS(price_elasticity_proxy) DESC;


-- ============================================================
-- PR5: Discount Effectiveness — Units Lift by Discount Tier
-- ============================================================
-- Business Insight: Does deeper discounting actually move more
--   units? If units don't lift proportionally to discount,
--   the markdown is margin destruction with no volume benefit.

WITH discount_tiers AS (
    SELECT
        dp.category,
        dp.description,
        f.units,
        f.discount_pct,
        -- Bucket discounts
        CASE
            WHEN f.discount_pct = 0             THEN 'Baseline (0%)'
            WHEN f.discount_pct <= 10           THEN 'Shallow (1–10%)'
            WHEN f.discount_pct <= 20           THEN 'Moderate (11–20%)'
            ELSE                                     'Deep (21%+)'
        END AS discount_tier
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
),
baseline_units AS (
    SELECT
        category,
        description,
        AVG(units) AS baseline_avg_units
    FROM discount_tiers
    WHERE discount_tier = 'Baseline (0%)'
    GROUP BY category, description
)
SELECT
    dt.category,
    dt.description,
    dt.discount_tier,
    ROUND(AVG(dt.units), 2)                         AS avg_units,
    ROUND(bu.baseline_avg_units, 2)                 AS baseline_units,
    ROUND(
        (AVG(dt.units) - bu.baseline_avg_units)
        / NULLIF(bu.baseline_avg_units, 0) * 100, 2
    )                                               AS units_lift_pct,
    COUNT(*)                                        AS row_count
FROM discount_tiers dt
LEFT JOIN baseline_units bu
    ON bu.category = dt.category AND bu.description = dt.description
GROUP BY dt.category, dt.description, dt.discount_tier, bu.baseline_avg_units
ORDER BY dt.category, dt.description, dt.discount_tier;


-- ============================================================
-- PR6: Price Gap vs Competitor (Base Price vs Actual Price)
-- ============================================================
-- Business Insight: The spread between base_price and actual
--   price is the promotional discount. Large gaps on recurring
--   weeks = structural below-shelf-price selling → brand dilution.

SELECT
    dp.description,
    dp.category,
    ROUND(AVG(f.base_price), 4)             AS avg_base_price,
    ROUND(AVG(f.price), 4)                  AS avg_actual_price,
    ROUND(AVG(f.price_gap), 4)              AS avg_price_gap,
    ROUND(AVG(f.discount_pct), 2)           AS avg_discount_pct,
    -- Weeks sold at a discount
    SUM(CASE WHEN f.price < f.base_price THEN 1 ELSE 0 END) AS weeks_discounted,
    COUNT(*)                                AS total_weeks,
    ROUND(
        SUM(CASE WHEN f.price < f.base_price THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                       AS pct_weeks_discounted,
    -- Revenue at discount vs full price
    ROUND(SUM(CASE WHEN f.price < f.base_price THEN f.spend ELSE 0 END), 2)
                                            AS revenue_at_discount,
    ROUND(SUM(CASE WHEN f.price >= f.base_price THEN f.spend ELSE 0 END), 2)
                                            AS revenue_at_full_price
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.description, dp.category
ORDER BY avg_discount_pct DESC;


-- ============================================================
-- PR7: Price by Store Segment (Do Upscale stores charge more?)
-- ============================================================
-- Business Insight: Validates that price segmentation is
--   actually implemented in shelf pricing across the store estate.

SELECT
    dp.category,
    ds.seg_value_name,
    ROUND(AVG(f.price), 4)              AS avg_price,
    ROUND(AVG(f.base_price), 4)         AS avg_base_price,
    ROUND(AVG(f.discount_pct), 2)       AS avg_discount_pct,
    ROUND(MIN(f.price), 4)              AS min_price,
    ROUND(MAX(f.price), 4)              AS max_price,
    -- Price premium vs VALUE segment (correlated subquery)
    ROUND(
        AVG(f.price) - (
            SELECT AVG(f2.price)
            FROM marts.fact_sales f2
            INNER JOIN marts.dim_store ds2 ON ds2.store_num = f2.store_num
            INNER JOIN marts.dim_product dp2 ON dp2.upc = f2.upc
            WHERE ds2.seg_value_name = 'VALUE'
            AND dp2.category = dp.category
        ), 4
    )                                   AS price_premium_vs_value
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY dp.category, ds.seg_value_name
ORDER BY dp.category, avg_price DESC;

-- ============================================================
-- Business Recommendation:
--   1. Elastic products (|elasticity| > 1) are candidates for
--      tactical price reductions to grow volume.
--   2. Products discounted >50% of weeks (PR6) have structurally
--      impaired base prices — consider price architecture reset.
--   3. Price band analysis (PR2) shows the "sweet spot" price
--      range with highest volume — use as promotional target price.
--   4. Upscale stores should price 5–10% above Value to maintain
--      segment positioning (PR7 validates this).
--
-- Interview Questions:
--   Q: How do you approximate price elasticity in SQL?
--   A: Segment data into price quartiles using NTILE(4). Compare
--      average units at Q1 (lowest price) vs Q4 (highest price).
--      Elasticity proxy = (% change in units) / (% change in price).
--      This is a simplification — true elasticity requires OLS regression.
-- ============================================================
