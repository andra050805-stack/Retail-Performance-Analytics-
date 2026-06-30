-- ============================================================
-- 19_views.sql
-- SQL Retail Analytics — Views & Materialized View Specs
-- ============================================================
-- Business Objective:
--   Create reusable view layer that abstracts complexity from
--   BI tool users and downstream data consumers. Views act as
--   a "semantic layer" — hiding join logic and column naming
--   conventions from business users who just want clean tables.
--
-- View Strategy:
--   - Standard views: for ad-hoc queries, always fresh data
--   - Materialized views: for heavy dashboards, scheduled refresh
--   - Security views: row-level filters for multi-tenant access
--
-- SQL Concepts Demonstrated:
--   CREATE VIEW, CREATE MATERIALIZED VIEW, column aliasing,
--   CTEs within views, layered view references
-- ============================================================


-- ============================================================
-- V1: vw_fact_enriched — Full Fact with All Dimensions
-- ============================================================
-- Purpose: One-stop joined view. BI users can query this
--   without knowing how the star schema joins together.
--   Includes all dimension attributes alongside fact measures.

CREATE OR REPLACE VIEW marts.vw_fact_enriched AS
SELECT
    -- Calendar
    dc.week_end_date,
    dc.year,
    dc.quarter,
    dc.month,
    dc.month_name,
    dc.week_of_year,
    dc.is_holiday_season,

    -- Product
    dp.upc,
    dp.description          AS product_name,
    dp.category,
    dp.sub_category,
    dp.manufacturer,
    dp.product_size,
    dp.category_code,

    -- Store
    ds.store_num,
    ds.store_name,
    ds.city,
    ds.state,
    ds.seg_value_name       AS store_segment,
    ds.sales_area_size_num  AS store_sqft,
    ds.store_size_band,
    ds.avg_weekly_baskets,

    -- Fact measures
    f.units,
    f.visits,
    f.hhs,
    f.spend,
    f.price,
    f.base_price,
    f.feature,
    f.display,
    f.tpr_only,
    f.discount_pct,
    f.price_gap,
    f.revenue_per_visit,
    f.units_per_hh,
    f.spend_per_hh,
    f.promo_type,
    f.is_promoted

FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num;

COMMENT ON VIEW marts.vw_fact_enriched IS
    'Fully enriched fact view. Use this as the base for most BI queries.';


-- ============================================================
-- V2: vw_weekly_summary — Weekly Revenue & Volume Aggregates
-- ============================================================
-- Purpose: Pre-aggregated weekly view for time series charts.

CREATE OR REPLACE VIEW marts.vw_weekly_summary AS
SELECT
    dc.week_end_date,
    dc.year,
    dc.quarter,
    dc.month,
    dc.month_name,
    dc.week_of_year,
    dc.is_holiday_season,
    ROUND(SUM(f.spend), 2)                          AS total_revenue,
    SUM(f.units)                                    AS total_units,
    SUM(f.visits)                                   AS total_visits,
    SUM(f.hhs)                                      AS total_hhs,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
    ROUND(AVG(f.price), 4)                          AS avg_price,
    ROUND(AVG(f.discount_pct), 4)                   AS avg_discount_pct,
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                               AS promo_rate_pct,
    -- Rolling averages (pre-computed for dashboard speed)
    ROUND(AVG(SUM(f.spend)) OVER (
        ORDER BY dc.week_end_date
        ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ), 2)                                           AS rolling_4w_avg_revenue,
    ROUND(AVG(SUM(f.spend)) OVER (
        ORDER BY dc.week_end_date
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ), 2)                                           AS rolling_12w_avg_revenue
FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
GROUP BY dc.week_end_date, dc.year, dc.quarter, dc.month,
         dc.month_name, dc.week_of_year, dc.is_holiday_season;

COMMENT ON VIEW marts.vw_weekly_summary IS
    'Weekly aggregated view with rolling averages. Use for trend dashboards.';


-- ============================================================
-- V3: vw_product_performance — Product Scorecard
-- ============================================================
-- Purpose: Product-level summary for product management dashboards.

CREATE OR REPLACE VIEW marts.vw_product_performance AS
WITH product_totals AS (
    SELECT
        f.upc,
        ROUND(SUM(f.spend), 4)      AS total_revenue,
        SUM(f.units)                AS total_units,
        SUM(f.visits)               AS total_visits,
        SUM(f.hhs)                  AS total_hhs,
        ROUND(AVG(f.price), 4)      AS avg_price,
        ROUND(AVG(f.discount_pct), 4) AS avg_discount_pct,
        ROUND(
            SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
        )                           AS promo_rate_pct,
        ROUND(AVG(f.revenue_per_visit), 4) AS avg_basket_value,
        ROUND(AVG(f.units_per_hh), 4)      AS avg_units_per_hh
    FROM marts.fact_sales f
    GROUP BY f.upc
)
SELECT
    dp.upc,
    dp.description          AS product_name,
    dp.category,
    dp.sub_category,
    dp.manufacturer,
    dp.product_size,
    pt.total_revenue,
    pt.total_units,
    pt.total_visits,
    pt.total_hhs,
    pt.avg_price,
    pt.avg_discount_pct,
    pt.promo_rate_pct,
    pt.avg_basket_value,
    pt.avg_units_per_hh,
    RANK() OVER (ORDER BY pt.total_revenue DESC)    AS portfolio_revenue_rank,
    RANK() OVER (PARTITION BY dp.category ORDER BY pt.total_revenue DESC) AS category_revenue_rank,
    ROUND(pt.total_revenue * 100.0 / SUM(pt.total_revenue) OVER (), 2) AS portfolio_share_pct,
    ps.abc_class
FROM product_totals pt
INNER JOIN marts.dim_product dp ON dp.upc = pt.upc
LEFT JOIN marts.agg_product_summary ps ON ps.upc = pt.upc;

COMMENT ON VIEW marts.vw_product_performance IS
    'Product scorecard with rankings, ABC class, and basket metrics.';


-- ============================================================
-- V4: vw_store_performance — Store Scorecard
-- ============================================================

CREATE OR REPLACE VIEW marts.vw_store_performance AS
WITH store_totals AS (
    SELECT
        f.store_num,
        ROUND(SUM(f.spend), 4)      AS total_revenue,
        SUM(f.units)                AS total_units,
        SUM(f.visits)               AS total_visits,
        SUM(f.hhs)                  AS total_hhs,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4)  AS avg_basket_value,
        ROUND(AVG(f.discount_pct), 4) AS avg_discount_pct,
        ROUND(
            SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
        )                           AS promo_rate_pct
    FROM marts.fact_sales f
    GROUP BY f.store_num
)
SELECT
    ds.store_num,
    ds.store_name,
    ds.city,
    ds.state,
    ds.seg_value_name   AS store_segment,
    ds.store_size_band,
    ds.sales_area_size_num,
    ds.avg_weekly_baskets,
    st.total_revenue,
    st.total_units,
    st.total_visits,
    st.total_hhs,
    st.avg_basket_value,
    st.avg_discount_pct,
    st.promo_rate_pct,
    ROUND(st.total_revenue / NULLIF(ds.sales_area_size_num, 0), 6) AS revenue_per_sqft,
    RANK() OVER (ORDER BY st.total_revenue DESC) AS global_revenue_rank,
    RANK() OVER (PARTITION BY ds.seg_value_name ORDER BY st.total_revenue DESC) AS segment_rank,
    RANK() OVER (PARTITION BY ds.state ORDER BY st.total_revenue DESC) AS state_rank
FROM store_totals st
INNER JOIN marts.dim_store ds ON ds.store_num = st.store_num;

COMMENT ON VIEW marts.vw_store_performance IS
    'Store scorecard with global, segment, and state-level rankings.';


-- ============================================================
-- V5: vw_promotion_summary — Promotion Performance
-- ============================================================

CREATE OR REPLACE VIEW marts.vw_promotion_summary AS
SELECT
    dp.category,
    dp.description      AS product_name,
    f.promo_type,
    COUNT(*)            AS total_rows,
    ROUND(AVG(f.units), 2) AS avg_units,
    ROUND(AVG(f.spend), 4) AS avg_revenue,
    ROUND(AVG(f.price), 4) AS avg_price,
    ROUND(AVG(f.discount_pct), 2) AS avg_discount_pct,
    ROUND(AVG(f.revenue_per_visit), 4) AS avg_basket_value
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category, dp.description, f.promo_type;

COMMENT ON VIEW marts.vw_promotion_summary IS
    'Promotion type performance by product. Use for promo planning.';


-- ============================================================
-- V6: vw_category_state — Category Revenue by State
-- ============================================================
-- Purpose: Geographic breakdown for regional management teams.

CREATE OR REPLACE VIEW marts.vw_category_state AS
SELECT
    ds.state,
    dp.category,
    COUNT(DISTINCT ds.store_num)                AS store_count,
    ROUND(SUM(f.spend), 2)                      AS total_revenue,
    ROUND(SUM(f.spend) / COUNT(DISTINCT ds.store_num), 2) AS revenue_per_store,
    ROUND(AVG(f.discount_pct), 2)               AS avg_discount_pct,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY ds.state, dp.category;


-- ============================================================
-- MATERIALIZED VIEW SPECIFICATIONS
-- ============================================================
-- Materialized views pre-compute expensive aggregations and
-- store the result physically. Queries run against the stored
-- result — 10–100× faster for dashboards vs live fact table scans.
--
-- When to use materialized views:
--   - Dashboard queries that take > 5 seconds on live fact
--   - Queries that run 100+ times per day from BI tools
--   - Scheduled reporting where slight data lag is acceptable


-- MV1: Weekly portfolio summary (refresh daily)
CREATE MATERIALIZED VIEW marts.mv_weekly_portfolio
WITH DATA AS
SELECT
    dc.week_end_date,
    dc.year,
    dc.quarter,
    ROUND(SUM(f.spend), 2) AS total_revenue,
    SUM(f.units) AS total_units,
    SUM(f.visits) AS total_visits,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
    ROUND(AVG(f.discount_pct), 4) AS avg_discount_pct,
    ROUND(SUM(CASE WHEN f.is_promoted THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 2) AS promo_rate_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
GROUP BY dc.week_end_date, dc.year, dc.quarter;

-- Refresh command (run via Airflow/cron daily at 06:00):
-- REFRESH MATERIALIZED VIEW marts.mv_weekly_portfolio;


-- MV2: Category × segment summary (refresh daily)
CREATE MATERIALIZED VIEW marts.mv_category_segment
WITH DATA AS
SELECT
    dp.category,
    ds.seg_value_name,
    ROUND(SUM(f.spend), 2)      AS total_revenue,
    SUM(f.units)                AS total_units,
    ROUND(AVG(f.price), 4)      AS avg_price,
    ROUND(AVG(f.discount_pct), 4) AS avg_discount_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
GROUP BY dp.category, ds.seg_value_name;


-- MV3: Product summary (refresh weekly)
CREATE MATERIALIZED VIEW marts.mv_product_summary
WITH DATA AS
SELECT
    f.upc,
    dp.description,
    dp.category,
    dp.manufacturer,
    ROUND(SUM(f.spend), 2) AS total_revenue,
    SUM(f.units) AS total_units,
    ROUND(AVG(f.price), 4) AS avg_price,
    ROUND(AVG(f.discount_pct), 4) AS avg_discount_pct,
    ROUND(SUM(CASE WHEN f.is_promoted THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 2) AS promo_rate_pct
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY f.upc, dp.description, dp.category, dp.manufacturer;


-- ============================================================
-- Index Recommendations for Views:
--   Views: no direct indexes (they query base tables)
--   Materialized Views: add indexes to support filter patterns
--
-- CREATE INDEX ON marts.mv_weekly_portfolio (week_end_date);
-- CREATE INDEX ON marts.mv_category_segment (category);
-- CREATE INDEX ON marts.mv_product_summary (category);
-- CREATE INDEX ON marts.mv_product_summary (total_revenue DESC);
-- ============================================================
