-- ============================================================
-- 17_kpi_dashboard.sql
-- SQL Retail Analytics — Executive KPI Dashboard
-- ============================================================
-- Business Objective:
--   Produce a complete executive-level dashboard using a single
--   SQL query (or minimal set). This is the "CEO's morning
--   email" — all critical metrics in one view. Designed to
--   power BI tools (Tableau, Looker, Power BI, Metabase) via
--   a materialized view or scheduled refresh.
--
-- Business Question:
--   What is the overall health of the retail portfolio,
--   and who are the current winners across every dimension?
--
-- SQL Concepts Demonstrated:
--   CTEs, conditional aggregation, window functions,
--   scalar subqueries, UNION ALL (metric assembly pattern),
--   correlated subquery for "best X" metrics
-- ============================================================


-- ============================================================
-- DASHBOARD QUERY 1: Executive Summary — One Row Per Metric
-- ============================================================
-- This "metric assembly" pattern uses UNION ALL to build a
-- tidy key-value dashboard output — perfect for BI tools that
-- need a vertical metric table.

WITH
-- Core totals
totals AS (
    SELECT
        ROUND(SUM(f.spend), 2)                                          AS total_revenue,
        SUM(f.units)                                                    AS total_units,
        SUM(f.visits)                                                   AS total_visits,
        SUM(f.hhs)                                                      AS total_hhs,
        COUNT(*)                                                        AS total_rows,
        COUNT(DISTINCT f.store_num)                                     AS total_stores,
        COUNT(DISTINCT f.upc)                                           AS total_products,
        COUNT(DISTINCT f.date_key)                                      AS total_weeks,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)              AS avg_basket_value,
        ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.visits), 0), 4)       AS avg_basket_size,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)                 AS avg_revenue_per_hh,
        ROUND(AVG(f.price), 4)                                         AS avg_selling_price,
        ROUND(AVG(f.discount_pct), 4)                                  AS avg_discount_pct,
        ROUND(SUM(CASE WHEN f.is_promoted    THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS promo_rate_pct,
        ROUND(SUM(CASE WHEN f.feature  = 1   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS feature_rate_pct,
        ROUND(SUM(CASE WHEN f.display  = 1   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS display_rate_pct,
        ROUND(SUM(CASE WHEN f.tpr_only = 1   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS tpr_rate_pct
    FROM marts.fact_sales f
),
-- YoY growth (last full year vs prior full year)
yoy AS (
    SELECT
        ROUND(SUM(CASE WHEN dc.year = (SELECT MAX(year) FROM marts.dim_calendar) THEN f.spend ELSE 0 END), 2) AS this_year_rev,
        ROUND(SUM(CASE WHEN dc.year = (SELECT MAX(year) - 1 FROM marts.dim_calendar) THEN f.spend ELSE 0 END), 2) AS last_year_rev
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
),
-- Best category
best_category AS (
    SELECT dp.category AS best_cat
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.category
    ORDER BY SUM(f.spend) DESC
    LIMIT 1
),
-- Best product
best_product AS (
    SELECT dp.description AS best_prod
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.description
    ORDER BY SUM(f.spend) DESC
    LIMIT 1
),
-- Best store
best_store AS (
    SELECT ds.store_name AS best_store
    FROM marts.fact_sales f
    INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
    GROUP BY ds.store_name
    ORDER BY SUM(f.spend) DESC
    LIMIT 1
),
-- Best state
best_state AS (
    SELECT ds.state AS best_state
    FROM marts.fact_sales f
    INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
    GROUP BY ds.state
    ORDER BY SUM(f.spend) DESC
    LIMIT 1
)
-- UNION ALL: assemble metric rows
SELECT 'total_revenue'          AS metric, CAST(total_revenue AS VARCHAR)          AS value, '💰 Total Revenue'             AS label FROM totals
UNION ALL SELECT 'total_units',         CAST(total_units AS VARCHAR),         '📦 Total Units'              FROM totals
UNION ALL SELECT 'total_visits',        CAST(total_visits AS VARCHAR),        '🛒 Total Visits'             FROM totals
UNION ALL SELECT 'total_hhs',           CAST(total_hhs AS VARCHAR),           '🏠 Total Households'         FROM totals
UNION ALL SELECT 'total_stores',        CAST(total_stores AS VARCHAR),        '🏪 Stores'                   FROM totals
UNION ALL SELECT 'total_products',      CAST(total_products AS VARCHAR),      '🏷️ Products'                 FROM totals
UNION ALL SELECT 'total_weeks',         CAST(total_weeks AS VARCHAR),         '📅 Weeks of Data'            FROM totals
UNION ALL SELECT 'avg_basket_value',    CAST(avg_basket_value AS VARCHAR),    '🧺 Avg Basket Value ($)'     FROM totals
UNION ALL SELECT 'avg_basket_size',     CAST(avg_basket_size AS VARCHAR),     '📊 Avg Basket Size (units)'  FROM totals
UNION ALL SELECT 'avg_revenue_per_hh',  CAST(avg_revenue_per_hh AS VARCHAR),  '👤 Avg Revenue per HH ($)'   FROM totals
UNION ALL SELECT 'avg_selling_price',   CAST(avg_selling_price AS VARCHAR),   '🏷️ Avg Selling Price ($)'    FROM totals
UNION ALL SELECT 'avg_discount_pct',    CAST(avg_discount_pct AS VARCHAR),    '🎯 Avg Discount (%)'         FROM totals
UNION ALL SELECT 'promo_rate_pct',      CAST(promo_rate_pct AS VARCHAR),      '📣 Promo Rate (%)'           FROM totals
UNION ALL SELECT 'feature_rate_pct',    CAST(feature_rate_pct AS VARCHAR),    '📰 Feature Rate (%)'         FROM totals
UNION ALL SELECT 'display_rate_pct',    CAST(display_rate_pct AS VARCHAR),    '🖼️ Display Rate (%)'         FROM totals
UNION ALL SELECT 'tpr_rate_pct',        CAST(tpr_rate_pct AS VARCHAR),        '💸 TPR Rate (%)'             FROM totals
UNION ALL SELECT 'yoy_revenue_growth_pct',
    CAST(ROUND((this_year_rev - last_year_rev) / NULLIF(last_year_rev, 0) * 100, 2) AS VARCHAR),
    '📈 YoY Revenue Growth (%)'
FROM yoy
UNION ALL SELECT 'best_category',       best_cat,                             '🥇 Best Category'            FROM best_category
UNION ALL SELECT 'best_product',        best_prod,                            '🥇 Best Product'             FROM best_product
UNION ALL SELECT 'best_store',          best_store,                           '🥇 Best Store'               FROM best_store
UNION ALL SELECT 'best_state',          best_state,                           '🥇 Best State'               FROM best_state;


-- ============================================================
-- DASHBOARD QUERY 2: Category Scorecard (One Row per Category)
-- ============================================================

SELECT
    dp.category,
    ROUND(SUM(f.spend), 2)                                          AS total_revenue,
    ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2)    AS revenue_share_pct,
    SUM(f.units)                                                    AS total_units,
    SUM(f.visits)                                                   AS total_visits,
    SUM(f.hhs)                                                      AS total_hhs,
    ROUND(AVG(f.price), 4)                                         AS avg_price,
    ROUND(AVG(f.discount_pct), 2)                                  AS avg_discount_pct,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)              AS avg_basket_value,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)                 AS avg_revenue_per_hh,
    ROUND(SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS promo_rate_pct,
    RANK() OVER (ORDER BY SUM(f.spend) DESC)                        AS revenue_rank
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category
ORDER BY total_revenue DESC;


-- ============================================================
-- DASHBOARD QUERY 3: Weekly Pulse — Last 8 Weeks
-- ============================================================
-- Business Use: "Last N weeks" trend for weekly ops meetings.

WITH recent_weeks AS (
    SELECT
        dc.week_end_date,
        dc.year,
        dc.week_of_year,
        ROUND(SUM(f.spend), 2) AS weekly_revenue,
        SUM(f.units)           AS weekly_units,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
        ROUND(AVG(f.discount_pct), 2) AS avg_discount_pct,
        ROUND(
            SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
        ) AS promo_rate_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.week_end_date, dc.year, dc.week_of_year
    ORDER BY dc.week_end_date DESC
    LIMIT 8
)
SELECT
    week_end_date,
    year,
    week_of_year,
    weekly_revenue,
    weekly_units,
    avg_basket_value,
    avg_discount_pct,
    promo_rate_pct,
    LAG(weekly_revenue) OVER (ORDER BY week_end_date) AS prev_week,
    ROUND(
        (weekly_revenue - LAG(weekly_revenue) OVER (ORDER BY week_end_date))
        / NULLIF(LAG(weekly_revenue) OVER (ORDER BY week_end_date), 0) * 100, 2
    ) AS wow_growth_pct
FROM recent_weeks
ORDER BY week_end_date DESC;


-- ============================================================
-- DASHBOARD QUERY 4: Store Segment Scorecard
-- ============================================================

SELECT
    ds.seg_value_name,
    COUNT(DISTINCT ds.store_num)                                    AS store_count,
    ROUND(SUM(f.spend), 2)                                          AS total_revenue,
    ROUND(SUM(f.spend) / COUNT(DISTINCT ds.store_num), 2)          AS revenue_per_store,
    ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2)    AS revenue_share_pct,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)              AS avg_basket_value,
    ROUND(AVG(f.discount_pct), 2)                                  AS avg_discount_pct,
    ROUND(SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS promo_rate_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.seg_value_name
ORDER BY total_revenue DESC;


-- ============================================================
-- DASHBOARD QUERY 5: Top 10 Products + Bottom 5 Summary
-- ============================================================
(
    SELECT
        'TOP 10' AS group_label,
        RANK() OVER (ORDER BY SUM(f.spend) DESC) AS rank_pos,
        dp.description,
        dp.category,
        dp.manufacturer,
        ROUND(SUM(f.spend), 2) AS total_revenue,
        ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2) AS portfolio_share_pct,
        SUM(f.units) AS total_units
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.description, dp.category, dp.manufacturer
    ORDER BY total_revenue DESC
    LIMIT 10
)
UNION ALL
(
    SELECT
        'BOTTOM 5',
        RANK() OVER (ORDER BY SUM(f.spend) ASC),
        dp.description,
        dp.category,
        dp.manufacturer,
        ROUND(SUM(f.spend), 2),
        ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2),
        SUM(f.units)
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.description, dp.category, dp.manufacturer
    ORDER BY total_revenue ASC
    LIMIT 5
)
ORDER BY group_label, rank_pos;

-- ============================================================
-- Materialized View Recommendation:
--   CREATE MATERIALIZED VIEW dashboard_kpi_summary AS
--   (the executive summary query above)
--   WITH DATA;
--
--   Refresh: REFRESH MATERIALIZED VIEW dashboard_kpi_summary;
--   Schedule: Daily at 06:00 via cron or Airflow DAG.
--
-- BI Tool Integration:
--   Connect Tableau / Power BI / Looker directly to:
--   - marts.agg_weekly_store_category (trend charts)
--   - marts.agg_product_summary (product scorecards)
--   - marts.agg_store_summary (store maps)
--   - dashboard_kpi_summary (KPI tiles)
-- ============================================================
