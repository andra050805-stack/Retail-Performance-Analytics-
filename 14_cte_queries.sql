-- ============================================================
-- 14_cte_queries.sql
-- SQL Retail Analytics — Complex CTE Queries
-- ============================================================
-- Business Objective:
--   Demonstrate mastery of Common Table Expressions (CTEs):
--   linear chains, multi-branch, self-referential, and
--   recursive. CTEs make complex multi-step analytics readable,
--   maintainable, and reusable across teams.
--
-- SQL Concepts Demonstrated:
--   WITH, chained CTEs, branching CTEs, recursive CTE,
--   correlated subquery vs CTE tradeoff, CTE + window function
-- ============================================================


-- ============================================================
-- CTE1: Multi-Branch CTE — Promo vs Baseline Comparison
-- ============================================================
-- Business Insight: Clean separation of promoted vs baseline
--   aggregations, then JOIN them for side-by-side comparison.
--   More readable and maintainable than a monolithic subquery.

WITH
-- Branch 1: Baseline (no promo) metrics per product
baseline AS (
    SELECT
        f.upc,
        AVG(f.units)        AS baseline_avg_units,
        AVG(f.spend)        AS baseline_avg_revenue,
        AVG(f.price)        AS baseline_avg_price,
        COUNT(*)            AS baseline_weeks
    FROM marts.fact_sales f
    WHERE f.promo_type = 'NONE'
    GROUP BY f.upc
),
-- Branch 2: Promoted metrics per product × promo type
promoted AS (
    SELECT
        f.upc,
        f.promo_type,
        AVG(f.units)        AS promo_avg_units,
        AVG(f.spend)        AS promo_avg_revenue,
        AVG(f.price)        AS promo_avg_price,
        COUNT(*)            AS promo_weeks
    FROM marts.fact_sales f
    WHERE f.promo_type != 'NONE'
    GROUP BY f.upc, f.promo_type
),
-- Branch 3: Product dimension enrichment
product_info AS (
    SELECT upc, description, category, manufacturer
    FROM marts.dim_product
),
-- Final: Combine all branches
combined AS (
    SELECT
        p.upc,
        pi.description,
        pi.category,
        pi.manufacturer,
        pr.promo_type,
        ROUND(b.baseline_avg_units, 2)      AS baseline_units,
        ROUND(pr.promo_avg_units, 2)        AS promo_units,
        ROUND(
            (pr.promo_avg_units - b.baseline_avg_units)
            / NULLIF(b.baseline_avg_units, 0) * 100, 2
        )                                   AS units_lift_pct,
        ROUND(b.baseline_avg_price, 4)      AS baseline_price,
        ROUND(pr.promo_avg_price, 4)        AS promo_price,
        ROUND(
            (b.baseline_avg_price - pr.promo_avg_price)
            / NULLIF(b.baseline_avg_price, 0) * 100, 2
        )                                   AS price_cut_pct,
        b.baseline_weeks,
        pr.promo_weeks
    FROM promoted pr
    INNER JOIN baseline b    ON b.upc = pr.upc
    INNER JOIN product_info pi ON pi.upc = pr.upc
)
SELECT *
FROM combined
ORDER BY category, units_lift_pct DESC;


-- ============================================================
-- CTE2: Chained CTE — 5-Step Product Revenue Attribution
-- ============================================================
-- Business Insight: Step-by-step revenue pipeline from raw
--   to final ABC class with cumulative share. Each CTE builds
--   on the previous — exactly like a dbt model chain.

WITH
-- Step 1: Raw product revenue
step1_raw AS (
    SELECT
        f.upc,
        ROUND(SUM(f.spend), 4) AS total_revenue,
        SUM(f.units)            AS total_units
    FROM marts.fact_sales f
    GROUP BY f.upc
),
-- Step 2: Join product dimension
step2_enriched AS (
    SELECT
        s.upc,
        p.description,
        p.category,
        p.manufacturer,
        s.total_revenue,
        s.total_units
    FROM step1_raw s
    INNER JOIN marts.dim_product p ON p.upc = s.upc
),
-- Step 3: Compute revenue rank
step3_ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
        SUM(total_revenue) OVER ()                AS grand_total
    FROM step2_enriched
),
-- Step 4: Compute cumulative share
step4_cumulative AS (
    SELECT
        *,
        SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                       AS cumulative_revenue,
        ROUND(total_revenue / grand_total * 100, 2) AS revenue_share_pct
    FROM step3_ranked
),
-- Step 5: Assign ABC class
step5_classified AS (
    SELECT
        *,
        ROUND(cumulative_revenue / grand_total * 100, 2) AS cumulative_pct,
        CASE
            WHEN cumulative_revenue / grand_total <= 0.70 THEN 'A'
            WHEN cumulative_revenue / grand_total <= 0.90 THEN 'B'
            ELSE                                               'C'
        END AS abc_class
    FROM step4_cumulative
)
SELECT
    revenue_rank,
    abc_class,
    upc,
    description,
    category,
    manufacturer,
    ROUND(total_revenue, 2) AS total_revenue,
    total_units,
    revenue_share_pct,
    cumulative_pct
FROM step5_classified
ORDER BY revenue_rank;


-- ============================================================
-- CTE3: Recursive CTE — Date Spine Generator
-- ============================================================
-- Business Use: Generate a complete date spine for a given
--   range without a calendar table. Critical for zero-filling
--   time series gaps (missing weeks = zero sales).

WITH RECURSIVE date_spine AS (
    -- Anchor: dataset start date
    SELECT
        (SELECT MIN(week_end_date) FROM marts.fact_sales f
         INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key) AS wk_date,
        1 AS week_seq

    UNION ALL

    -- Recurse: add one week at a time
    SELECT
        CAST(wk_date + INTERVAL '7 days' AS DATE),
        week_seq + 1
    FROM date_spine
    WHERE wk_date < (
        SELECT MAX(week_end_date) FROM marts.dim_calendar
    )
)
SELECT
    week_seq,
    wk_date,
    EXTRACT(YEAR FROM wk_date)      AS year,
    EXTRACT(QUARTER FROM wk_date)   AS quarter,
    EXTRACT(MONTH FROM wk_date)     AS month,
    EXTRACT(WEEK FROM wk_date)      AS iso_week_num
FROM date_spine
ORDER BY week_seq;


-- ============================================================
-- CTE4: Store × Product Zero-Fill (Coverage Gap Analysis)
-- ============================================================
-- Business Insight: Which product-store-week combinations had
--   NO sales? These represent out-of-stock, distribution gaps,
--   or data collection errors. Needed for accurate averages.

WITH all_combos AS (
    -- All possible store × product combinations
    SELECT
        ds.store_num,
        dp.upc,
        dp.description,
        dp.category,
        ds.seg_value_name
    FROM marts.dim_store ds
    CROSS JOIN marts.dim_product dp
),
all_weeks AS (
    SELECT DISTINCT date_key, week_end_date
    FROM marts.dim_calendar
),
-- Full spine: store × product × week
full_spine AS (
    SELECT
        c.store_num,
        c.upc,
        c.description,
        c.category,
        c.seg_value_name,
        w.date_key,
        w.week_end_date
    FROM all_combos c
    CROSS JOIN all_weeks w
),
-- Actual sales
actual_sales AS (
    SELECT date_key, store_num, upc, spend, units
    FROM marts.fact_sales
)
SELECT
    fs.store_num,
    fs.upc,
    fs.description,
    fs.category,
    fs.seg_value_name,
    fs.week_end_date,
    COALESCE(a.spend, 0)    AS spend,
    COALESCE(a.units, 0)    AS units,
    CASE WHEN a.upc IS NULL THEN TRUE ELSE FALSE END AS is_zero_week
FROM full_spine fs
LEFT JOIN actual_sales a
    ON a.date_key = fs.date_key
    AND a.store_num = fs.store_num
    AND a.upc = fs.upc
-- Only show the gaps for the summary
WHERE a.upc IS NULL
ORDER BY fs.upc, fs.store_num, fs.week_end_date
LIMIT 1000;  -- limit for demo; in production, materialize this


-- ============================================================
-- CTE5: Top-N per Group — Top 3 Products per Category per Year
-- ============================================================
-- Business Use: "Podium" analysis — which products dominated
--   each category each year? Year-over-year podium shifts
--   signal competitive dynamics.

WITH yearly_product_revenue AS (
    SELECT
        dc.year,
        dp.category,
        dp.description,
        dp.manufacturer,
        ROUND(SUM(f.spend), 2) AS annual_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY dc.year, dp.category
            ORDER BY SUM(f.spend) DESC
        ) AS rank_in_cat_year
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.year, dp.category, dp.description, dp.manufacturer
)
SELECT
    year,
    category,
    rank_in_cat_year    AS podium_position,
    description,
    manufacturer,
    annual_revenue,
    -- Medal emoji
    CASE rank_in_cat_year
        WHEN 1 THEN '🥇'
        WHEN 2 THEN '🥈'
        WHEN 3 THEN '🥉'
    END AS medal
FROM yearly_product_revenue
WHERE rank_in_cat_year <= 3
ORDER BY year, category, rank_in_cat_year;
