-- ============================================================
-- 06_sales_analysis.sql
-- SQL Retail Analytics — Sales Trend Analysis
-- ============================================================
-- Business Objective:
--   Analyze revenue and volume trends across weekly, monthly,
--   and quarterly time granularities. Identify growth periods,
--   seasonality patterns, and inflection points aligned with
--   the ML notebook's time series chapter.
--
-- Business Questions:
--   Is the portfolio growing or declining over 156 weeks?
--   Which quarters and months drive the highest sales?
--   What is the YoY revenue growth rate?
--
-- SQL Concepts Demonstrated:
--   DATE_TRUNC, EXTRACT, LAG, LEAD, GROUP BY, ORDER BY,
--   window functions, CTEs, growth rate computation,
--   CASE WHEN, ROUND, NULLIF
-- ============================================================


-- ============================================================
-- S1: Weekly Revenue Trend — Full 156 Weeks
-- ============================================================
-- Business Insight: Baseline for the time series chapter.
--   Week-over-week comparison reveals seasonality spikes
--   and promotional event impacts.

SELECT
    dc.week_end_date,
    dc.year,
    dc.quarter,
    dc.month,
    dc.week_of_year,
    dc.is_holiday_season,

    -- Revenue & Volume
    ROUND(SUM(f.spend), 2)                          AS weekly_revenue,
    SUM(f.units)                                    AS weekly_units,
    SUM(f.visits)                                   AS weekly_visits,
    SUM(f.hhs)                                      AS weekly_hhs,

    -- Basket Metrics
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,

    -- Pricing
    ROUND(AVG(f.price), 4)                          AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                   AS avg_discount_pct,

    -- Promo Activity
    SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) AS promoted_rows,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                               AS promo_rate_pct,

    -- Week-over-week growth (using LAG)
    LAG(ROUND(SUM(f.spend), 2)) OVER (
        ORDER BY dc.week_end_date
    )                                               AS prev_week_revenue,
    ROUND(
        (SUM(f.spend) - LAG(SUM(f.spend)) OVER (ORDER BY dc.week_end_date))
        / NULLIF(LAG(SUM(f.spend)) OVER (ORDER BY dc.week_end_date), 0) * 100, 2
    )                                               AS wow_revenue_growth_pct

FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
GROUP BY
    dc.week_end_date, dc.year, dc.quarter, dc.month,
    dc.week_of_year, dc.is_holiday_season
ORDER BY dc.week_end_date;


-- ============================================================
-- S2: Monthly Revenue Trend
-- ============================================================
-- Business Insight: Smoother than weekly view; reveals seasonal
--   patterns. November–December typically show promotional spikes.

WITH monthly_sales AS (
    SELECT
        dc.year,
        dc.month,
        dc.month_name,
        ROUND(SUM(f.spend), 2)          AS monthly_revenue,
        SUM(f.units)                    AS monthly_units,
        SUM(f.visits)                   AS monthly_visits,
        ROUND(AVG(f.discount_pct), 2)   AS avg_discount_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.year, dc.month, dc.month_name
)
SELECT
    year,
    month,
    month_name,
    monthly_revenue,
    monthly_units,
    monthly_visits,
    avg_discount_pct,

    -- Month-over-month growth
    LAG(monthly_revenue) OVER (ORDER BY year, month)    AS prev_month_revenue,
    ROUND(
        (monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY year, month))
        / NULLIF(LAG(monthly_revenue) OVER (ORDER BY year, month), 0) * 100, 2
    )                                                   AS mom_revenue_growth_pct,

    -- Same month prior year (YoY)
    LAG(monthly_revenue, 12) OVER (ORDER BY year, month) AS same_month_last_year,
    ROUND(
        (monthly_revenue - LAG(monthly_revenue, 12) OVER (ORDER BY year, month))
        / NULLIF(LAG(monthly_revenue, 12) OVER (ORDER BY year, month), 0) * 100, 2
    )                                                   AS yoy_revenue_growth_pct,

    -- Running total
    ROUND(
        SUM(monthly_revenue) OVER (ORDER BY year, month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2
    )                                                   AS cumulative_revenue
FROM monthly_sales
ORDER BY year, month;


-- ============================================================
-- S3: Quarterly Revenue Analysis
-- ============================================================
-- Business Insight: Q4 typically spikes due to holiday promotions.
--   Q1 often dips as post-holiday consumer spending contracts.

WITH quarterly_sales AS (
    SELECT
        dc.year,
        dc.quarter,
        CONCAT(dc.year, '-Q', dc.quarter)       AS year_quarter,
        ROUND(SUM(f.spend), 2)                  AS quarterly_revenue,
        SUM(f.units)                            AS quarterly_units,
        SUM(f.visits)                           AS quarterly_visits,
        ROUND(AVG(f.discount_pct), 2)           AS avg_discount_pct,
        ROUND(
            SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
        )                                       AS promo_rate_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.year, dc.quarter
)
SELECT
    year_quarter,
    year,
    quarter,
    quarterly_revenue,
    quarterly_units,
    quarterly_visits,
    avg_discount_pct,
    promo_rate_pct,

    -- QoQ growth
    LAG(quarterly_revenue) OVER (ORDER BY year, quarter) AS prev_quarter_revenue,
    ROUND(
        (quarterly_revenue - LAG(quarterly_revenue) OVER (ORDER BY year, quarter))
        / NULLIF(LAG(quarterly_revenue) OVER (ORDER BY year, quarter), 0) * 100, 2
    )                                                    AS qoq_revenue_growth_pct,

    -- Same quarter prior year
    LAG(quarterly_revenue, 4) OVER (ORDER BY year, quarter) AS same_q_last_year,
    ROUND(
        (quarterly_revenue - LAG(quarterly_revenue, 4) OVER (ORDER BY year, quarter))
        / NULLIF(LAG(quarterly_revenue, 4) OVER (ORDER BY year, quarter), 0) * 100, 2
    )                                                    AS yoy_quarterly_growth_pct,

    -- Quarter's share of annual revenue
    ROUND(
        quarterly_revenue * 100.0
        / SUM(quarterly_revenue) OVER (PARTITION BY year), 2
    )                                                    AS pct_of_annual_revenue
FROM quarterly_sales
ORDER BY year, quarter;


-- ============================================================
-- S4: Annual Revenue Summary & YoY Growth
-- ============================================================
-- Business Question: What is the compound growth story?

WITH annual_sales AS (
    SELECT
        dc.year,
        ROUND(SUM(f.spend), 2)          AS annual_revenue,
        SUM(f.units)                    AS annual_units,
        SUM(f.visits)                   AS annual_visits,
        SUM(f.hhs)                      AS annual_hhs,
        COUNT(DISTINCT dc.week_end_date) AS weeks_in_year
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.year
)
SELECT
    year,
    annual_revenue,
    annual_units,
    annual_visits,
    annual_hhs,
    weeks_in_year,
    ROUND(annual_revenue / weeks_in_year, 2)     AS avg_weekly_revenue,
    LAG(annual_revenue) OVER (ORDER BY year)     AS prior_year_revenue,
    ROUND(
        (annual_revenue - LAG(annual_revenue) OVER (ORDER BY year))
        / NULLIF(LAG(annual_revenue) OVER (ORDER BY year), 0) * 100, 2
    )                                            AS yoy_revenue_growth_pct,
    ROUND(
        (annual_units - LAG(annual_units) OVER (ORDER BY year)) * 100.0
        / NULLIF(LAG(annual_units) OVER (ORDER BY year), 0), 2
    )                                            AS yoy_units_growth_pct
FROM annual_sales
ORDER BY year;


-- ============================================================
-- S5: Sales by Category Over Time (Category Trend Matrix)
-- ============================================================
-- Business Insight: Reveals whether categories are growing or
--   declining at different rates — useful for portfolio strategy.

SELECT
    dc.year,
    dc.quarter,
    dp.category,
    ROUND(SUM(f.spend), 2)                                      AS revenue,
    ROUND(
        SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (
            PARTITION BY dc.year, dc.quarter
        ), 2
    )                                                           AS pct_of_quarter_revenue,
    ROUND(
        SUM(f.spend) - LAG(SUM(f.spend)) OVER (
            PARTITION BY dp.category ORDER BY dc.year, dc.quarter
        ), 2
    )                                                           AS revenue_vs_prev_quarter
FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dc.year, dc.quarter, dp.category
ORDER BY dc.year, dc.quarter, revenue DESC;


-- ============================================================
-- S6: Holiday Season vs Non-Holiday Revenue
-- ============================================================
-- Business Insight: Is November-December a meaningful uplift period
--   in a grocery-adjacent dataset? Validates seasonal patterns
--   from notebook's time series decomposition.

SELECT
    dc.is_holiday_season,
    COUNT(DISTINCT dc.week_end_date)    AS week_count,
    ROUND(SUM(f.spend), 2)              AS total_revenue,
    ROUND(SUM(f.spend) / COUNT(DISTINCT dc.week_end_date), 2) AS avg_weekly_revenue,
    SUM(f.units)                        AS total_units,
    ROUND(AVG(f.discount_pct), 2)       AS avg_discount_pct,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                   AS promo_rate_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
GROUP BY dc.is_holiday_season;


-- ============================================================
-- S7: Revenue Growth by Store Segment Over Time
-- ============================================================
-- Business Question: Is the Upscale segment growing faster
--   than Value stores over the observation period?

SELECT
    dc.year,
    ds.seg_value_name,
    ROUND(SUM(f.spend), 2)                                      AS revenue,
    LAG(ROUND(SUM(f.spend), 2)) OVER (
        PARTITION BY ds.seg_value_name ORDER BY dc.year
    )                                                           AS prior_year_revenue,
    ROUND(
        (SUM(f.spend) - LAG(SUM(f.spend)) OVER (
            PARTITION BY ds.seg_value_name ORDER BY dc.year
        )) / NULLIF(LAG(SUM(f.spend)) OVER (
            PARTITION BY ds.seg_value_name ORDER BY dc.year
        ), 0) * 100, 2
    )                                                           AS yoy_growth_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY dc.year, ds.seg_value_name
ORDER BY dc.year, ds.seg_value_name;


-- ============================================================
-- S8: Best and Worst Performing Weeks
-- ============================================================
-- Business Insight: Identify peak revenue weeks (likely promo
--   or holiday events) and trough weeks (off-season, low-promo).

WITH weekly_revenue AS (
    SELECT
        dc.week_end_date,
        dc.year,
        dc.month_name,
        dc.is_holiday_season,
        ROUND(SUM(f.spend), 2)          AS weekly_revenue,
        SUM(f.units)                    AS weekly_units,
        ROUND(AVG(f.discount_pct), 2)   AS avg_discount_pct,
        ROUND(
            SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
        )                               AS promo_rate_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.week_end_date, dc.year, dc.month_name, dc.is_holiday_season
)
(
    -- Top 10 Weeks
    SELECT 'TOP 10' AS rank_group, RANK() OVER (ORDER BY weekly_revenue DESC) AS week_rank, *
    FROM weekly_revenue
    ORDER BY weekly_revenue DESC
    LIMIT 10
)
UNION ALL
(
    -- Bottom 10 Weeks
    SELECT 'BOTTOM 10', RANK() OVER (ORDER BY weekly_revenue ASC), *
    FROM weekly_revenue
    ORDER BY weekly_revenue ASC
    LIMIT 10
)
ORDER BY rank_group, week_rank;

-- ============================================================
-- Business Recommendation:
--   1. Use quarterly trend (S3) to set seasonal revenue targets.
--   2. Align promotional calendars with historically high-traffic
--      months to amplify natural demand uplift.
--   3. Investigate bottom-10 weeks (S8) for out-of-stock or
--      operational issues — these represent recoverable revenue.
--
-- Interview Questions:
--   Q: How do you compute YoY growth in SQL without self-join?
--   A: LAG(metric, N) OVER (ORDER BY year) where N = 4 for
--      quarterly or N = 12 for monthly YoY. Avoids the
--      complexity and performance cost of a self-join.
--
--   Q: What is the difference between LAG(col, 1) and LAG(col, 12)?
--   A: LAG(col, 1) = previous row's value; LAG(col, 12) =
--      value from 12 rows back. For monthly data ordered by
--      year+month, LAG(col, 12) gives same month last year.
-- ============================================================
