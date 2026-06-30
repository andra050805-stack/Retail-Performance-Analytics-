-- ============================================================
-- 13_window_functions.sql
-- SQL Retail Analytics — Window Functions Showcase
-- ============================================================
-- Business Objective:
--   Demonstrate comprehensive mastery of SQL window functions
--   for analytics engineering interviews. Each query solves
--   a real business problem using the appropriate window
--   function type, partition, frame, and order clause.
--
-- SQL Concepts Demonstrated:
--   ROW_NUMBER, RANK, DENSE_RANK, NTILE,
--   LAG, LEAD, FIRST_VALUE, LAST_VALUE,
--   SUM OVER, AVG OVER, COUNT OVER,
--   Running totals, rolling windows, moving average,
--   Percent of total, cumulative metrics
-- ============================================================


-- ============================================================
-- W1: ROW_NUMBER — Unique sequential rank within each category
-- ============================================================
-- Business Use: Assign a unique row identifier for deduplication
--   or pagination. Unlike RANK, no ties — every row is unique.

SELECT
    dp.category,
    dp.description,
    ROUND(SUM(f.spend), 2)          AS total_revenue,
    ROW_NUMBER() OVER (
        PARTITION BY dp.category
        ORDER BY SUM(f.spend) DESC
    )                               AS row_num_in_category,
    -- Compare to RANK and DENSE_RANK on same data
    RANK() OVER (
        PARTITION BY dp.category
        ORDER BY SUM(f.spend) DESC
    )                               AS rank_in_category,
    DENSE_RANK() OVER (
        PARTITION BY dp.category
        ORDER BY SUM(f.spend) DESC
    )                               AS dense_rank_in_category
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category, dp.description
ORDER BY dp.category, total_revenue DESC;


-- ============================================================
-- W2: NTILE — Quartile / Decile Segmentation
-- ============================================================
-- Business Use: Split stores into performance buckets without
--   using arbitrary cutoffs. Useful for investment tier decisions.

SELECT
    ds.store_num,
    ds.store_name,
    ds.seg_value_name,
    ROUND(SUM(f.spend), 2)          AS total_revenue,
    NTILE(4) OVER (ORDER BY SUM(f.spend) DESC)  AS revenue_quartile,
    NTILE(10) OVER (ORDER BY SUM(f.spend) DESC) AS revenue_decile,
    -- Label the quartile
    CASE NTILE(4) OVER (ORDER BY SUM(f.spend) DESC)
        WHEN 1 THEN 'Tier 1 — Top Performer'
        WHEN 2 THEN 'Tier 2 — Above Average'
        WHEN 3 THEN 'Tier 3 — Below Average'
        WHEN 4 THEN 'Tier 4 — Low Performer'
    END AS store_tier
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.store_num, ds.store_name, ds.seg_value_name
ORDER BY total_revenue DESC;


-- ============================================================
-- W3: LAG & LEAD — Period-over-Period Comparison
-- ============================================================
-- Business Use: Week-over-week delta and look-ahead for
--   forecasting context. LAG = backward; LEAD = forward.

WITH weekly_cat AS (
    SELECT
        dc.week_end_date,
        dp.category,
        ROUND(SUM(f.spend), 2) AS weekly_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dc.week_end_date, dp.category
)
SELECT
    week_end_date,
    category,
    weekly_revenue,

    -- LAG: previous week in same category
    LAG(weekly_revenue, 1) OVER (
        PARTITION BY category ORDER BY week_end_date
    )                       AS prev_week_revenue,

    -- LAG(n=4): same week 4 weeks ago
    LAG(weekly_revenue, 4) OVER (
        PARTITION BY category ORDER BY week_end_date
    )                       AS revenue_4w_ago,

    -- LAG(n=52): same week last year
    LAG(weekly_revenue, 52) OVER (
        PARTITION BY category ORDER BY week_end_date
    )                       AS revenue_52w_ago,

    -- LEAD: next week (useful for promotional look-ahead)
    LEAD(weekly_revenue, 1) OVER (
        PARTITION BY category ORDER BY week_end_date
    )                       AS next_week_revenue,

    -- WoW change
    ROUND(
        weekly_revenue - LAG(weekly_revenue, 1) OVER (
            PARTITION BY category ORDER BY week_end_date
        ), 2
    )                       AS wow_delta,
    ROUND(
        (weekly_revenue - LAG(weekly_revenue, 1) OVER (
            PARTITION BY category ORDER BY week_end_date
        )) / NULLIF(LAG(weekly_revenue, 1) OVER (
            PARTITION BY category ORDER BY week_end_date
        ), 0) * 100, 2
    )                       AS wow_pct_change
FROM weekly_cat
ORDER BY category, week_end_date;


-- ============================================================
-- W4: FIRST_VALUE & LAST_VALUE — Anchoring to Period Extremes
-- ============================================================
-- Business Use: Compare every week to the first week (baseline)
--   and last week (current). Reveals trajectory direction.

WITH weekly_rev AS (
    SELECT
        dc.week_end_date,
        ROUND(SUM(f.spend), 2) AS weekly_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.week_end_date
)
SELECT
    week_end_date,
    weekly_revenue,

    -- First week in dataset (anchor baseline)
    FIRST_VALUE(weekly_revenue) OVER (
        ORDER BY week_end_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_week_revenue,

    -- Last week in dataset (current endpoint)
    LAST_VALUE(weekly_revenue) OVER (
        ORDER BY week_end_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_week_revenue,

    -- Growth vs first week
    ROUND(
        (weekly_revenue - FIRST_VALUE(weekly_revenue) OVER (
            ORDER BY week_end_date ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )) / NULLIF(FIRST_VALUE(weekly_revenue) OVER (
            ORDER BY week_end_date ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ), 0) * 100, 2
    ) AS growth_vs_first_week_pct,

    -- Peak week of all time
    MAX(weekly_revenue) OVER (
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS all_time_peak_revenue,

    -- % of peak
    ROUND(weekly_revenue / NULLIF(MAX(weekly_revenue) OVER (
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ), 0) * 100, 2) AS pct_of_peak
FROM weekly_rev
ORDER BY week_end_date;


-- ============================================================
-- W5: SUM OVER — Running Total & Cumulative Revenue
-- ============================================================
-- Business Use: Track cumulative revenue to compare pace
--   against prior year or annual target.

SELECT
    dc.week_end_date,
    dc.year,
    dc.week_of_year,
    ROUND(SUM(f.spend), 2) AS weekly_revenue,

    -- Running total (all weeks)
    ROUND(SUM(SUM(f.spend)) OVER (
        ORDER BY dc.week_end_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2) AS cumulative_revenue,

    -- Running total within the year (reset each year)
    ROUND(SUM(SUM(f.spend)) OVER (
        PARTITION BY dc.year
        ORDER BY dc.week_end_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2) AS ytd_revenue,

    -- Running unit total
    SUM(SUM(f.units)) OVER (
        ORDER BY dc.week_end_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_units,

    -- Cumulative % of total revenue
    ROUND(
        SUM(SUM(f.spend)) OVER (
            ORDER BY dc.week_end_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(SUM(f.spend)) OVER () * 100, 2
    ) AS cumulative_pct_of_total

FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
GROUP BY dc.week_end_date, dc.year, dc.week_of_year
ORDER BY dc.week_end_date;


-- ============================================================
-- W6: AVG OVER — Rolling Moving Average (4W, 8W, 12W)
-- ============================================================
-- Business Use: Smooth weekly revenue noise to detect the
--   true underlying trend. Standard tool in retail forecasting.

SELECT
    dc.week_end_date,
    dp.category,
    ROUND(SUM(f.spend), 2) AS weekly_revenue,

    -- 4-week moving average (short-term trend)
    ROUND(AVG(SUM(f.spend)) OVER (
        PARTITION BY dp.category
        ORDER BY dc.week_end_date
        ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ), 2) AS ma_4w,

    -- 8-week moving average
    ROUND(AVG(SUM(f.spend)) OVER (
        PARTITION BY dp.category
        ORDER BY dc.week_end_date
        ROWS BETWEEN 7 PRECEDING AND CURRENT ROW
    ), 2) AS ma_8w,

    -- 12-week moving average (medium-term trend)
    ROUND(AVG(SUM(f.spend)) OVER (
        PARTITION BY dp.category
        ORDER BY dc.week_end_date
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ), 2) AS ma_12w,

    -- Is current week above or below its 12-week moving average?
    CASE
        WHEN SUM(f.spend) > AVG(SUM(f.spend)) OVER (
            PARTITION BY dp.category
            ORDER BY dc.week_end_date
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ) THEN 'Above MA'
        ELSE 'Below MA'
    END AS vs_ma_12w

FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dc.week_end_date, dp.category
ORDER BY dp.category, dc.week_end_date;


-- ============================================================
-- W7: COUNT OVER — Distinct Weeks a Product Sold
-- ============================================================
-- Business Use: Identify products that disappeared from shelves.
--   A product with fewer than 156 selling weeks may have been
--   discontinued or out-of-stock in certain stores.

SELECT
    dp.description,
    dp.category,
    f.store_num,
    COUNT(DISTINCT f.date_key) AS weeks_with_sales,
    156 AS total_weeks,
    156 - COUNT(DISTINCT f.date_key) AS missing_weeks,
    -- Rank by missing weeks (most gaps first)
    RANK() OVER (ORDER BY 156 - COUNT(DISTINCT f.date_key) DESC) AS missing_weeks_rank,
    ROUND(SUM(f.spend), 2) AS total_revenue
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.description, dp.category, f.store_num
HAVING COUNT(DISTINCT f.date_key) < 156
ORDER BY missing_weeks DESC
LIMIT 50;


-- ============================================================
-- W8: Percent of Total with PARTITION BY
-- ============================================================
-- Business Use: Revenue share computations — each product's
--   share within its category, each store's share within
--   its segment, etc.

SELECT
    dp.category,
    dp.description,
    ds.seg_value_name,
    ROUND(SUM(f.spend), 2) AS product_segment_revenue,

    -- Share of category
    ROUND(
        SUM(f.spend) * 100.0
        / SUM(SUM(f.spend)) OVER (PARTITION BY dp.category), 2
    ) AS pct_of_category_revenue,

    -- Share of segment
    ROUND(
        SUM(f.spend) * 100.0
        / SUM(SUM(f.spend)) OVER (PARTITION BY ds.seg_value_name), 2
    ) AS pct_of_segment_revenue,

    -- Share of total portfolio
    ROUND(
        SUM(f.spend) * 100.0
        / SUM(SUM(f.spend)) OVER (), 2
    ) AS pct_of_total_revenue

FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY dp.category, dp.description, ds.seg_value_name
ORDER BY dp.category, product_segment_revenue DESC;

-- ============================================================
-- Window Function Quick Reference:
--
-- | Function              | Use Case                        |
-- |-----------------------|---------------------------------|
-- | ROW_NUMBER()          | Unique sequential rank          |
-- | RANK()                | Rank with gaps on ties          |
-- | DENSE_RANK()          | Rank without gaps on ties       |
-- | NTILE(n)              | Equal-bucket segmentation       |
-- | LAG(col, n)           | Previous n rows value           |
-- | LEAD(col, n)          | Next n rows value               |
-- | FIRST_VALUE(col)      | First value in window           |
-- | LAST_VALUE(col)       | Last value in window (unbounded)|
-- | SUM() OVER (ORDER BY) | Running / cumulative total      |
-- | AVG() OVER (n PREC)   | Rolling moving average          |
-- | COUNT() OVER (PART)   | Count within partition          |
--
-- Interview Questions:
--   Q: What is the difference between ROWS and RANGE frame specs?
--   A: ROWS BETWEEN counts physical rows. RANGE BETWEEN counts
--      rows with the same ORDER BY value. For time series,
--      ROWS is almost always preferred (more precise control).
--
--   Q: How would you compute "percent of total" in SQL?
--   A: SUM(col) * 100.0 / SUM(SUM(col)) OVER () — the inner
--      SUM is the GROUP BY aggregate; the outer SUM OVER ()
--      is the grand total without any partition.
-- ============================================================
