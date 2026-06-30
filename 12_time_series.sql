-- ============================================================
-- 12_time_series.sql
-- SQL Retail Analytics — Time Series & Seasonality Analysis
-- ============================================================
-- Business Objective:
--   Implement SQL-based time series analysis to surface
--   seasonality, trend decomposition, and anomaly detection.
--   SQL supports the downstream time series ML models
--   (SARIMA/LSTM/Prophet) from ML notebook Chapter 12 by
--   preparing clean, feature-rich time series datasets.
--
-- Business Questions:
--   What is the revenue trend over 156 weeks?
--   Are there repeating seasonal patterns?
--   Which weeks are statistical anomalies?
--
-- SQL Concepts Demonstrated:
--   LAG, LEAD, FIRST_VALUE, LAST_VALUE, rolling windows,
--   SUM/AVG OVER, moving average, CTEs, date functions
-- ============================================================


-- ============================================================
-- TS1: Full Time Series with Rolling Averages
-- ============================================================
-- Business Insight: Foundation for all time series plots.
--   Rolling 4-week avg smooths weekly noise; 12-week avg
--   reveals the underlying trend. LAG/LEAD for context.

WITH weekly_totals AS (
    SELECT
        dc.week_end_date,
        dc.year,
        dc.quarter,
        dc.month,
        dc.week_of_year,
        dc.is_holiday_season,
        ROUND(SUM(f.spend), 2)          AS weekly_revenue,
        SUM(f.units)                    AS weekly_units,
        SUM(f.visits)                   AS weekly_visits,
        SUM(f.hhs)                      AS weekly_hhs,
        ROUND(AVG(f.discount_pct), 4)   AS avg_discount_pct,
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) AS promo_rows
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.week_end_date, dc.year, dc.quarter, dc.month,
             dc.week_of_year, dc.is_holiday_season
)
SELECT
    week_end_date,
    year,
    quarter,
    month,
    week_of_year,
    is_holiday_season,
    weekly_revenue,
    weekly_units,
    weekly_visits,
    avg_discount_pct,

    -- Previous and next week (LAG / LEAD)
    LAG(weekly_revenue, 1) OVER (ORDER BY week_end_date) AS prev_week_revenue,
    LEAD(weekly_revenue, 1) OVER (ORDER BY week_end_date) AS next_week_revenue,

    -- Week-over-week change
    ROUND(
        weekly_revenue - LAG(weekly_revenue, 1) OVER (ORDER BY week_end_date), 2
    ) AS wow_revenue_delta,
    ROUND(
        (weekly_revenue - LAG(weekly_revenue, 1) OVER (ORDER BY week_end_date))
        / NULLIF(LAG(weekly_revenue, 1) OVER (ORDER BY week_end_date), 0) * 100, 2
    ) AS wow_revenue_pct,

    -- 4-Week Rolling Average (smooths weekly variance)
    ROUND(AVG(weekly_revenue) OVER (
        ORDER BY week_end_date
        ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_4w_avg_revenue,

    -- 12-Week Rolling Average (reveals underlying trend)
    ROUND(AVG(weekly_revenue) OVER (
        ORDER BY week_end_date
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_12w_avg_revenue,

    -- 52-Week Rolling Average (long-term trend baseline)
    ROUND(AVG(weekly_revenue) OVER (
        ORDER BY week_end_date
        ROWS BETWEEN 51 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_52w_avg_revenue,

    -- Running cumulative revenue
    ROUND(SUM(weekly_revenue) OVER (
        ORDER BY week_end_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2) AS cumulative_revenue,

    -- Same week last year (52-week lag)
    LAG(weekly_revenue, 52) OVER (ORDER BY week_end_date) AS same_week_last_year,
    ROUND(
        (weekly_revenue - LAG(weekly_revenue, 52) OVER (ORDER BY week_end_date))
        / NULLIF(LAG(weekly_revenue, 52) OVER (ORDER BY week_end_date), 0) * 100, 2
    ) AS yoy_weekly_growth_pct,

    -- First and last value (anchor points for trend direction)
    FIRST_VALUE(weekly_revenue) OVER (ORDER BY week_end_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_week_revenue,
    LAST_VALUE(weekly_revenue) OVER (ORDER BY week_end_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_week_revenue

FROM weekly_totals
ORDER BY week_end_date;


-- ============================================================
-- TS2: Rolling Revenue by Category (Multi-Series)
-- ============================================================
-- Business Insight: Each category's rolling trend independently.
--   Detects if one category is growing while another declines.

SELECT
    dc.week_end_date,
    dp.category,
    ROUND(SUM(f.spend), 2)          AS weekly_revenue,

    -- 4-Week Rolling Average per category
    ROUND(AVG(SUM(f.spend)) OVER (
        PARTITION BY dp.category
        ORDER BY dc.week_end_date
        ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ), 2) AS cat_rolling_4w_avg,

    -- 12-Week Rolling Average per category
    ROUND(AVG(SUM(f.spend)) OVER (
        PARTITION BY dp.category
        ORDER BY dc.week_end_date
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ), 2) AS cat_rolling_12w_avg,

    -- Category's % of total portfolio that week
    ROUND(
        SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (PARTITION BY dc.week_end_date), 2
    ) AS pct_of_weekly_portfolio

FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
GROUP BY dc.week_end_date, dp.category
ORDER BY dp.category, dc.week_end_date;


-- ============================================================
-- TS3: Seasonality — Average Revenue by Week-of-Year (Pattern)
-- ============================================================
-- Business Insight: Averaging across all years reveals the
--   seasonal "shape" — which weeks of the year consistently
--   over- or under-perform. This is the SQL equivalent of
--   seasonal decomposition.

SELECT
    dc.week_num,       -- ISO week 1–52
    dc.month_name,
    COUNT(DISTINCT dc.year)         AS years_observed,
    ROUND(AVG(weekly_revenue), 2)   AS avg_revenue_this_week,
    ROUND(MIN(weekly_revenue), 2)   AS min_revenue_this_week,
    ROUND(MAX(weekly_revenue), 2)   AS max_revenue_this_week,
    ROUND(STDDEV(weekly_revenue), 2) AS stddev_revenue,
    -- Seasonal index: this week's avg vs overall weekly avg
    ROUND(
        AVG(weekly_revenue) / (SELECT AVG(s2.weekly_revenue) FROM (
            SELECT dc2.week_end_date, SUM(f2.spend) AS weekly_revenue
            FROM marts.fact_sales f2
            INNER JOIN marts.dim_calendar dc2 ON dc2.date_key = f2.date_key
            GROUP BY dc2.week_end_date
        ) s2), 4
    ) AS seasonal_index
FROM (
    SELECT
        dc.week_end_date,
        dc.year,
        dc.week_num,
        dc.month_name,
        ROUND(SUM(f.spend), 2) AS weekly_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.week_end_date, dc.year, dc.week_num, dc.month_name
) weekly_data
INNER JOIN marts.dim_calendar dc ON dc.week_end_date = weekly_data.week_end_date
GROUP BY dc.week_num, dc.month_name
ORDER BY dc.week_num;


-- ============================================================
-- TS4: Anomaly Detection — Weeks Beyond ±2 Standard Deviations
-- ============================================================
-- Business Insight: Statistical outlier weeks likely represent
--   major promotional events, store closures, or data issues.
--   These weeks should be investigated before inclusion in ML models.

WITH weekly_stats AS (
    SELECT
        dc.week_end_date,
        dc.year,
        dc.month_name,
        dc.is_holiday_season,
        ROUND(SUM(f.spend), 2) AS weekly_revenue,
        SUM(f.units)           AS weekly_units
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.week_end_date, dc.year, dc.month_name, dc.is_holiday_season
),
global_stats AS (
    SELECT
        AVG(weekly_revenue)    AS mean_revenue,
        STDDEV(weekly_revenue) AS stddev_revenue
    FROM weekly_stats
)
SELECT
    ws.week_end_date,
    ws.year,
    ws.month_name,
    ws.is_holiday_season,
    ws.weekly_revenue,
    ws.weekly_units,
    ROUND(gs.mean_revenue, 2)   AS mean_revenue,
    ROUND(gs.stddev_revenue, 2) AS stddev_revenue,
    ROUND(
        (ws.weekly_revenue - gs.mean_revenue) / NULLIF(gs.stddev_revenue, 0), 4
    )                           AS z_score,
    CASE
        WHEN ABS((ws.weekly_revenue - gs.mean_revenue) / NULLIF(gs.stddev_revenue, 0)) > 2
        THEN '⚠️ ANOMALY'
        ELSE '✓ NORMAL'
    END                         AS anomaly_flag
FROM weekly_stats ws
CROSS JOIN global_stats gs
ORDER BY ABS((ws.weekly_revenue - gs.mean_revenue) / NULLIF(gs.stddev_revenue, 0)) DESC;


-- ============================================================
-- TS5: Feature Dataset for Time Series ML Models
-- ============================================================
-- Business Insight: This query produces the final feature-
--   engineered dataset that feeds into SARIMA/Prophet/LSTM
--   models in the ML notebook Chapter 12. SQL prepares all
--   temporal features; Python handles the modeling.

SELECT
    dc.week_end_date,
    dc.year,
    dc.quarter,
    dc.month,
    dc.week_num,
    dc.week_of_year,
    dc.is_holiday_season,

    -- Target variable
    ROUND(SUM(f.spend), 4)          AS total_revenue,
    SUM(f.units)                    AS total_units,

    -- Lag features (for autoregressive models)
    LAG(SUM(f.spend), 1)  OVER (ORDER BY dc.week_end_date) AS lag_1w_revenue,
    LAG(SUM(f.spend), 4)  OVER (ORDER BY dc.week_end_date) AS lag_4w_revenue,
    LAG(SUM(f.spend), 13) OVER (ORDER BY dc.week_end_date) AS lag_13w_revenue,
    LAG(SUM(f.spend), 52) OVER (ORDER BY dc.week_end_date) AS lag_52w_revenue,

    -- Rolling features
    ROUND(AVG(SUM(f.spend)) OVER (ORDER BY dc.week_end_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW), 4)
        AS rolling_4w_mean,
    ROUND(AVG(SUM(f.spend)) OVER (ORDER BY dc.week_end_date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 4)
        AS rolling_12w_mean,
    ROUND(STDDEV(SUM(f.spend)) OVER (ORDER BY dc.week_end_date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 4)
        AS rolling_12w_std,

    -- Promotion features (exogenous variables)
    ROUND(AVG(f.discount_pct), 4)   AS avg_discount_pct,
    SUM(CASE WHEN f.feature = 1  THEN 1 ELSE 0 END) AS feature_count,
    SUM(CASE WHEN f.display = 1  THEN 1 ELSE 0 END) AS display_count,
    SUM(CASE WHEN f.tpr_only = 1 THEN 1 ELSE 0 END) AS tpr_only_count,
    SUM(CASE WHEN f.is_promoted  THEN 1 ELSE 0 END) AS promo_rows,

    -- Category breakdown (multi-variate time series)
    ROUND(SUM(CASE WHEN dp.category = 'BAG SNACKS'            THEN f.spend ELSE 0 END), 4) AS snacks_revenue,
    ROUND(SUM(CASE WHEN dp.category = 'COLD CEREAL'           THEN f.spend ELSE 0 END), 4) AS cereal_revenue,
    ROUND(SUM(CASE WHEN dp.category = 'FROZEN PIZZA'          THEN f.spend ELSE 0 END), 4) AS pizza_revenue,
    ROUND(SUM(CASE WHEN dp.category = 'ORAL HYGIENE PRODUCTS' THEN f.spend ELSE 0 END), 4) AS oral_revenue

FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dc.week_end_date, dc.year, dc.quarter, dc.month,
         dc.week_num, dc.week_of_year, dc.is_holiday_season
ORDER BY dc.week_end_date;

-- ============================================================
-- Business Recommendation:
--   1. Export TS5 to Python as the ML model input dataset.
--      Add SARIMA for univariate and Vector AR for multivariate.
--   2. Weeks with seasonal_index > 1.2 (TS3) are natural
--      candidates for intensified promotional support.
--   3. Anomaly weeks (TS4) should be flagged in the ML
--      training set or handled as missing values.
--
-- Interview Questions:
--   Q: How do you compute a rolling average in SQL?
--   A: AVG(col) OVER (ORDER BY date_col
--      ROWS BETWEEN N-1 PRECEDING AND CURRENT ROW)
--      where N is the window size (e.g. 4 for 4-week rolling avg).
--
--   Q: What is a seasonal index?
--   A: It compares a period's average value to the overall average.
--      Index > 1 = above-average season; < 1 = below-average.
--      It quantifies how much a specific period over/under performs.
-- ============================================================
