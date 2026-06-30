-- ============================================================
-- 11_customer_behavior.sql
-- SQL Retail Analytics — Customer Behavior Analysis
-- ============================================================
-- Business Objective:
--   Analyze household-level purchase behavior: basket size,
--   visit frequency, spend per household, and category
--   cross-purchase patterns. Aligned with ML notebook
--   Chapter 11 (Customer Behavior) and Chapter 13 (Clustering).
--
-- Business Questions:
--   Which categories have the most loyal households?
--   How does household purchase intensity differ by segment?
--   What is the visit frequency and basket composition?
--
-- SQL Concepts Demonstrated:
--   CTEs, window functions, CASE WHEN, conditional aggregation,
--   COALESCE, NTILE (customer segmentation), HAVING, subquery
-- ============================================================


-- ============================================================
-- CB1: Basket Metrics Summary by Category × Segment
-- ============================================================

SELECT
    dp.category,
    ds.seg_value_name,

    -- Basket size (units per visit)
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.visits), 0), 4)    AS avg_basket_size,

    -- Basket value (spend per visit)
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)           AS avg_basket_value,

    -- Revenue per household
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)              AS avg_revenue_per_hh,

    -- Units per household
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.hhs), 0), 4)       AS avg_units_per_hh,

    -- Visits per household (frequency)
    ROUND(SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0), 4)      AS avg_visits_per_hh,

    -- Total volume
    SUM(f.units)                                                  AS total_units,
    SUM(f.hhs)                                                    AS total_hhs,
    ROUND(SUM(f.spend), 2)                                        AS total_revenue

FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
WHERE f.visits > 0 AND f.hhs > 0
GROUP BY dp.category, ds.seg_value_name
ORDER BY dp.category, avg_basket_value DESC;


-- ============================================================
-- CB2: Purchase Intensity Segmentation
-- ============================================================
-- Business Insight: Segment product-store combinations into
--   Low / Medium / High purchase intensity quintiles using
--   NTILE(5) on units_per_hh. High intensity = loyal buyers.
--   Aligned with notebook Chapter 11 intensity analysis.

WITH intensity_base AS (
    SELECT
        f.store_num,
        f.upc,
        dp.category,
        dp.description,
        ds.seg_value_name,
        ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.hhs), 0), 4) AS units_per_hh,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)        AS spend_per_hh,
        ROUND(SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0), 4) AS visits_per_hh,
        ROUND(SUM(f.spend), 2)                                  AS total_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
    WHERE f.hhs > 0
    GROUP BY f.store_num, f.upc, dp.category, dp.description, ds.seg_value_name
)
SELECT
    NTILE(5) OVER (ORDER BY units_per_hh DESC)  AS intensity_quintile,
    CASE NTILE(5) OVER (ORDER BY units_per_hh DESC)
        WHEN 1 THEN 'Q1 — VERY HIGH'
        WHEN 2 THEN 'Q2 — HIGH'
        WHEN 3 THEN 'Q3 — MEDIUM'
        WHEN 4 THEN 'Q4 — LOW'
        WHEN 5 THEN 'Q5 — VERY LOW'
    END                                          AS intensity_label,
    store_num,
    upc,
    description,
    category,
    seg_value_name,
    units_per_hh,
    spend_per_hh,
    visits_per_hh,
    total_revenue
FROM intensity_base
ORDER BY intensity_quintile, units_per_hh DESC;


-- ============================================================
-- CB3: Customer Visit Frequency Distribution
-- ============================================================
-- Business Insight: How often do households purchase each
--   category? High visits/HH = habitual buyers (cereals),
--   low = infrequent (mouthwash). Visit frequency drives
--   category marketing strategy.

SELECT
    dp.category,
    -- Classify visit frequency
    CASE
        WHEN SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0) < 1.1 THEN 'Low (< 1.1 visits/HH)'
        WHEN SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0) < 1.5 THEN 'Medium (1.1–1.5)'
        WHEN SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0) < 2.0 THEN 'High (1.5–2.0)'
        ELSE                                                          'Very High (2.0+)'
    END                                                             AS frequency_band,
    ROUND(SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0), 4)        AS avg_visits_per_hh,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)                AS avg_spend_per_hh,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.hhs), 0), 4)         AS avg_units_per_hh,
    SUM(f.hhs)                                                      AS total_hhs,
    ROUND(SUM(f.spend), 2)                                          AS total_revenue
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
WHERE f.hhs > 0 AND f.visits > 0
GROUP BY dp.category
ORDER BY avg_visits_per_hh DESC;


-- ============================================================
-- CB4: Household Revenue per Store by Segment
-- ============================================================
-- Business Question: Are Upscale store households more valuable
--   (higher spend per HH) than Value store households?

SELECT
    ds.seg_value_name,
    dp.category,
    COUNT(DISTINCT ds.store_num)                                AS store_count,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)            AS avg_spend_per_hh,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.hhs), 0), 4)     AS avg_units_per_hh,
    ROUND(SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0), 4)    AS avg_visits_per_hh,
    -- Premium vs baseline (VALUE segment = baseline)
    ROUND(
        SUM(f.spend) / NULLIF(SUM(f.hhs), 0)
        - (
            SELECT SUM(f2.spend) / NULLIF(SUM(f2.hhs), 0)
            FROM marts.fact_sales f2
            INNER JOIN marts.dim_store ds2 ON ds2.store_num = f2.store_num
            INNER JOIN marts.dim_product dp2 ON dp2.upc = f2.upc
            WHERE ds2.seg_value_name = 'VALUE'
            AND dp2.category = dp.category
            AND f2.hhs > 0
        ), 4
    )                                                           AS premium_vs_value_stores
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
WHERE f.hhs > 0
GROUP BY ds.seg_value_name, dp.category
ORDER BY dp.category, avg_spend_per_hh DESC;


-- ============================================================
-- CB5: Category Cross-Purchase Pattern (SELF JOIN on Store+Week)
-- ============================================================
-- Business Insight: In which store-weeks does Category A sell
--   alongside Category B? Approximates basket co-occurrence.
--   High co-occurrence = bundling or cross-display opportunity.
--   This is the SQL equivalent of the association rules concept
--   from the notebook's recommendation engine chapter.

WITH weekly_store_category AS (
    SELECT
        f.date_key,
        f.store_num,
        dp.category,
        ROUND(SUM(f.spend), 4)  AS cat_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY f.date_key, f.store_num, dp.category
    HAVING SUM(f.spend) > 0
)
SELECT
    a.category        AS category_a,
    b.category        AS category_b,
    COUNT(*)          AS co_occurrence_weeks,
    -- % of category A's weeks where B is also selling
    ROUND(
        COUNT(*) * 100.0
        / (SELECT COUNT(DISTINCT w.date_key || '-' || w.store_num::TEXT)
           FROM weekly_store_category w WHERE w.category = a.category), 2
    )                 AS pct_of_cat_a_weeks_with_b,
    ROUND(AVG(a.cat_revenue + b.cat_revenue), 2) AS avg_combined_weekly_revenue
FROM weekly_store_category a
INNER JOIN weekly_store_category b
    ON a.date_key = b.date_key
    AND a.store_num = b.store_num
    AND a.category < b.category    -- avoid duplicate pairs
GROUP BY a.category, b.category
ORDER BY co_occurrence_weeks DESC;


-- ============================================================
-- CB6: Units per Visit by Category and Promotion Status
-- ============================================================
-- Business Question: "What is the impact on units/visit of
--   promotions?" (Direct question from dunnhumby guide.)

SELECT
    dp.category,
    CASE WHEN f.is_promoted THEN 'PROMOTED' ELSE 'BASELINE' END AS promo_status,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.visits), 0), 4)    AS units_per_visit,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)           AS spend_per_visit,
    ROUND(SUM(f.hhs) * 1.0 / NULLIF(SUM(f.visits), 0), 4)      AS hhs_per_visit,
    COUNT(*)                                                      AS row_count
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
WHERE f.visits > 0
GROUP BY dp.category, CASE WHEN f.is_promoted THEN 'PROMOTED' ELSE 'BASELINE' END
ORDER BY dp.category, promo_status;


-- ============================================================
-- CB7: Household Reach vs Frequency Matrix
-- ============================================================
-- Business Insight: The Reach × Frequency matrix. High reach +
--   high frequency = high loyalty category (Cereal).
--   Low reach + low frequency = niche / opportunistic (Mouthwash).

WITH hh_freq AS (
    SELECT
        dp.category,
        f.store_num,
        f.date_key,
        SUM(f.hhs)                                          AS hhs,
        SUM(f.visits)                                       AS visits
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.category, f.store_num, f.date_key
)
SELECT
    category,
    ROUND(AVG(hhs), 1)                          AS avg_hhs_per_store_week,
    ROUND(AVG(visits), 1)                       AS avg_visits_per_store_week,
    ROUND(AVG(visits * 1.0 / NULLIF(hhs, 0)), 4) AS avg_visit_frequency,
    -- Segment: High/Low reach × High/Low frequency
    CASE
        WHEN AVG(hhs) >= (SELECT AVG(hhs2) FROM hh_freq hhs2)
             AND AVG(visits * 1.0 / NULLIF(hhs, 0)) >= (SELECT AVG(visits2 * 1.0 / NULLIF(hhs2, 0)) FROM hh_freq hhs2)
             THEN 'High Reach × High Frequency (STAR)'
        WHEN AVG(hhs) >= (SELECT AVG(hhs2) FROM hh_freq hhs2)
             THEN 'High Reach × Low Frequency (DESTINATION)'
        WHEN AVG(visits * 1.0 / NULLIF(hhs, 0)) >= (SELECT AVG(visits2 * 1.0 / NULLIF(hhs2, 0)) FROM hh_freq hhs2)
             THEN 'Low Reach × High Frequency (LOYAL NICHE)'
        ELSE      'Low Reach × Low Frequency (OPPORTUNITY)'
    END                                         AS customer_matrix_segment
FROM hh_freq
WHERE hhs > 0
GROUP BY category
ORDER BY avg_hhs_per_store_week DESC;


-- ============================================================
-- CB8: Households With Below-Average Spend per Category
-- ============================================================
-- Business Insight: HAVING clause applied to household metrics.
--   Product-store combinations where HH spend is below average
--   for that category — these are underperforming pockets.

SELECT
    dp.category,
    ds.seg_value_name,
    ds.state,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4) AS spend_per_hh,
    COUNT(DISTINCT f.store_num)                       AS store_count,
    ROUND(SUM(f.spend), 2)                            AS total_revenue
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
WHERE f.hhs > 0
GROUP BY dp.category, ds.seg_value_name, ds.state
HAVING SUM(f.spend) / NULLIF(SUM(f.hhs), 0) <
    (
        SELECT AVG(f2.spend_per_hh)
        FROM marts.fact_sales f2
        INNER JOIN marts.dim_product dp2 ON dp2.upc = f2.upc
        WHERE dp2.category = dp.category
        AND f2.spend_per_hh IS NOT NULL
    )
ORDER BY dp.category, spend_per_hh ASC;

-- ============================================================
-- Business Recommendation:
--   1. STAR categories (CB7 = High Reach × High Frequency):
--      maximize shelf space and auto-replenishment.
--   2. High purchase intensity quintile Q1 (CB2): target for
--      loyalty programs and personalized offers.
--   3. Category cross-purchase data (CB5) should inform
--      store planogram adjacency decisions.
--
-- Interview Questions:
--   Q: What is the difference between "visits" and "households"?
--   A: HHS = unique households who purchased (reach metric).
--      VISITS = unique baskets / transactions. One HH can visit
--      multiple times in a week, so VISITS ≥ HHS always.
--      visits/HHS = purchase frequency per household.
-- ============================================================
