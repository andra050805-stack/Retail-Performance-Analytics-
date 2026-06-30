-- ============================================================
-- 07_product_analysis.sql
-- SQL Retail Analytics — Product Performance Analysis
-- ============================================================
-- Business Objective:
--   Rank all 58 products by revenue, units, and profitability
--   proxy. Identify the Pareto 80/20 products, ABC classes,
--   and market share by category. Aligned with ML notebook
--   Chapters 2 (EDA), 7 (Product Analysis), 13 (Clustering).
--
-- Business Questions:
--   Which products drive 80% of revenue?
--   Which products are underperformers / tail SKUs?
--   What is each product's market share within its category?
--
-- SQL Concepts Demonstrated:
--   RANK, DENSE_RANK, NTILE, ROW_NUMBER, cumulative SUM,
--   CASE WHEN, CTEs, subqueries, window partitioning
-- ============================================================


-- ============================================================
-- P1: Full Product Revenue Ranking
-- ============================================================
-- Business Insight: Simple but essential. Retail teams scan
--   this weekly to spot underperformers and protect champions.

SELECT
    RANK() OVER (ORDER BY SUM(f.spend) DESC)            AS revenue_rank,
    dp.upc,
    dp.description,
    dp.category,
    dp.sub_category,
    dp.manufacturer,
    dp.product_size,

    -- Revenue & Volume
    ROUND(SUM(f.spend), 2)                              AS total_revenue,
    SUM(f.units)                                        AS total_units,
    SUM(f.visits)                                       AS total_visits,
    SUM(f.hhs)                                          AS total_hhs,

    -- Pricing
    ROUND(AVG(f.price), 4)                              AS avg_price,
    ROUND(MIN(f.price), 4)                              AS min_price,
    ROUND(MAX(f.price), 4)                              AS max_price,
    ROUND(AVG(f.discount_pct), 2)                       AS avg_discount_pct,

    -- Share of total portfolio revenue
    ROUND(
        SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 2
    )                                                   AS portfolio_revenue_share_pct,

    -- Promo behaviour
    ROUND(
        SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                   AS promo_rate_pct

FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.upc, dp.description, dp.category, dp.sub_category,
         dp.manufacturer, dp.product_size
ORDER BY total_revenue DESC;


-- ============================================================
-- P2: Pareto Analysis — 80/20 Revenue Contribution
-- ============================================================
-- Business Insight: Classic Pareto principle. In most retail
--   portfolios, ~20% of SKUs drive ~80% of revenue.
--   Identify these "A products" to protect shelf space,
--   prioritize promotions, and optimize inventory.

WITH product_revenue AS (
    SELECT
        f.upc,
        dp.description,
        dp.category,
        dp.manufacturer,
        ROUND(SUM(f.spend), 4)      AS product_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY f.upc, dp.description, dp.category, dp.manufacturer
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY product_revenue DESC)     AS revenue_rank,
        SUM(product_revenue) OVER ()                    AS grand_total,
        SUM(product_revenue) OVER (
            ORDER BY product_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                               AS cumulative_revenue
    FROM product_revenue
)
SELECT
    revenue_rank,
    upc,
    description,
    category,
    manufacturer,
    ROUND(product_revenue, 2)               AS product_revenue,
    ROUND(product_revenue / grand_total * 100, 2) AS revenue_share_pct,
    ROUND(cumulative_revenue / grand_total * 100, 2) AS cumulative_share_pct,

    -- Pareto classification
    CASE
        WHEN cumulative_revenue / grand_total <= 0.80 THEN 'TOP 80% (Core SKU)'
        WHEN cumulative_revenue / grand_total <= 0.95 THEN 'NEXT 15% (Secondary)'
        ELSE                                               'TAIL 5% (Candidate for rationalization)'
    END                                     AS pareto_class,

    -- What % of SKU count gets us to this cumulative revenue?
    ROUND(revenue_rank * 100.0 / 58, 1)    AS sku_count_pct
FROM ranked
ORDER BY revenue_rank;


-- ============================================================
-- P3: ABC Classification (Full Detail)
-- ============================================================
-- Business Insight: ABC is a standard inventory & pricing tool.
--   A = top 70% cumulative → invest in availability & display
--   B = 70–90% → maintain & optimize
--   C = 90–100% → review for range rationalization

WITH product_cum AS (
    SELECT
        f.upc,
        dp.description,
        dp.category,
        dp.manufacturer,
        ROUND(SUM(f.spend), 4)              AS total_revenue,
        SUM(f.units)                        AS total_units,
        RANK() OVER (ORDER BY SUM(f.spend) DESC) AS revenue_rank,
        ROUND(SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (), 4) AS revenue_share_pct,
        SUM(SUM(f.spend)) OVER (
            ORDER BY SUM(f.spend) DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(SUM(f.spend)) OVER ()       AS cumulative_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY f.upc, dp.description, dp.category, dp.manufacturer
)
SELECT
    revenue_rank,
    upc,
    description,
    category,
    manufacturer,
    ROUND(total_revenue, 2)             AS total_revenue,
    total_units,
    ROUND(revenue_share_pct, 2)         AS revenue_share_pct,
    ROUND(cumulative_pct * 100, 2)      AS cumulative_pct,
    CASE
        WHEN cumulative_pct <= 0.70 THEN 'A'
        WHEN cumulative_pct <= 0.90 THEN 'B'
        ELSE                             'C'
    END                                 AS abc_class,
    CASE
        WHEN cumulative_pct <= 0.70 THEN 'High Value — Protect & Invest'
        WHEN cumulative_pct <= 0.90 THEN 'Mid Value — Optimize'
        ELSE                             'Low Value — Review'
    END                                 AS abc_strategy
FROM product_cum
ORDER BY revenue_rank;


-- ============================================================
-- P4: Market Share Within Category
-- ============================================================
-- Business Insight: Category-level competitive positioning.
--   Which products dominate their category, and which compete
--   for scraps? Aligned with notebook Chapter 7.

SELECT
    dp.category,
    dp.description,
    dp.manufacturer,
    ROUND(SUM(f.spend), 2)                                      AS product_revenue,
    -- Share of category revenue
    ROUND(
        SUM(f.spend) * 100.0 / SUM(SUM(f.spend)) OVER (PARTITION BY dp.category), 2
    )                                                           AS category_market_share_pct,
    -- Rank within category
    RANK() OVER (
        PARTITION BY dp.category ORDER BY SUM(f.spend) DESC
    )                                                           AS category_revenue_rank,
    -- Total category revenue (for reference)
    ROUND(SUM(SUM(f.spend)) OVER (PARTITION BY dp.category), 2) AS category_total_revenue
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
GROUP BY dp.category, dp.description, dp.manufacturer
ORDER BY dp.category, product_revenue DESC;


-- ============================================================
-- P5: Top 5 and Bottom 5 Products per Category
-- ============================================================
-- Business Question: Who are the category champions and laggards?

WITH product_cat_rank AS (
    SELECT
        dp.category,
        dp.description,
        dp.manufacturer,
        dp.product_size,
        ROUND(SUM(f.spend), 2)              AS total_revenue,
        SUM(f.units)                        AS total_units,
        ROUND(AVG(f.price), 4)              AS avg_price,
        RANK() OVER (
            PARTITION BY dp.category ORDER BY SUM(f.spend) DESC
        )                                   AS rank_top,
        RANK() OVER (
            PARTITION BY dp.category ORDER BY SUM(f.spend) ASC
        )                                   AS rank_bottom,
        COUNT(*) OVER (PARTITION BY dp.category) AS products_in_category
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.category, dp.description, dp.manufacturer, dp.product_size
)
SELECT
    category,
    CASE WHEN rank_top <= 5 THEN 'TOP 5' ELSE 'BOTTOM 5' END   AS performance_band,
    CASE WHEN rank_top <= 5 THEN rank_top ELSE rank_bottom END   AS band_rank,
    description,
    manufacturer,
    product_size,
    total_revenue,
    total_units,
    avg_price
FROM product_cat_rank
WHERE rank_top <= 5 OR rank_bottom <= 5
ORDER BY category, performance_band, band_rank;


-- ============================================================
-- P6: Decile Analysis — Products by Revenue Decile
-- ============================================================
-- Business Insight: NTILE(10) splits 58 products into
--   revenue deciles. Decile 1 = top 10%, Decile 10 = bottom 10%.

WITH product_rev AS (
    SELECT
        dp.upc,
        dp.description,
        dp.category,
        ROUND(SUM(f.spend), 2) AS total_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.upc, dp.description, dp.category
)
SELECT
    NTILE(10) OVER (ORDER BY total_revenue DESC)    AS revenue_decile,
    upc,
    description,
    category,
    total_revenue,
    ROUND(total_revenue * 100.0 / SUM(total_revenue) OVER (), 2) AS revenue_share_pct
FROM product_rev
ORDER BY revenue_decile, total_revenue DESC;


-- ============================================================
-- P7: Products With Declining Sales (Last 52 Weeks vs Prior)
-- ============================================================
-- Business Insight: Identifies products losing momentum.
--   Declining products need category review, pricing action,
--   or range rationalization.

WITH last_52 AS (
    SELECT
        f.upc,
        dp.description,
        dp.category,
        SUM(f.spend) AS revenue_last_52
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    WHERE dc.week_of_year > (SELECT MAX(week_of_year) - 52 FROM marts.dim_calendar)
    GROUP BY f.upc, dp.description, dp.category
),
prior_52 AS (
    SELECT
        f.upc,
        SUM(f.spend) AS revenue_prior_52
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    WHERE dc.week_of_year BETWEEN
        (SELECT MAX(week_of_year) - 104 FROM marts.dim_calendar) AND
        (SELECT MAX(week_of_year) - 52 FROM marts.dim_calendar)
    GROUP BY f.upc
)
SELECT
    l.upc,
    l.description,
    l.category,
    ROUND(l.revenue_last_52, 2)     AS revenue_last_52w,
    ROUND(p.revenue_prior_52, 2)    AS revenue_prior_52w,
    ROUND(
        (l.revenue_last_52 - p.revenue_prior_52)
        / NULLIF(p.revenue_prior_52, 0) * 100, 2
    )                               AS revenue_change_pct,
    CASE
        WHEN l.revenue_last_52 < p.revenue_prior_52 THEN '▼ DECLINING'
        WHEN l.revenue_last_52 > p.revenue_prior_52 THEN '▲ GROWING'
        ELSE                                              '─ STABLE'
    END                             AS trend_label
FROM last_52 l
LEFT JOIN prior_52 p ON p.upc = l.upc
ORDER BY revenue_change_pct ASC;


-- ============================================================
-- P8: Units per Household by Product (Purchase Intensity)
-- ============================================================
-- Business Insight: High units/HH = purchase intensity =
--   loyal, habitual buyers. Target for loyalty programs.

SELECT
    dp.description,
    dp.category,
    dp.manufacturer,
    ROUND(SUM(f.units) * 1.0 / NULLIF(SUM(f.hhs), 0), 4)  AS units_per_hh,
    ROUND(SUM(f.spend) / NULLIF(SUM(f.hhs), 0), 4)         AS spend_per_hh,
    ROUND(SUM(f.visits) * 1.0 / NULLIF(SUM(f.hhs), 0), 4) AS visits_per_hh,
    ROUND(SUM(f.spend), 2)                                  AS total_revenue,
    RANK() OVER (ORDER BY SUM(f.units) * 1.0 / NULLIF(SUM(f.hhs), 0) DESC) AS intensity_rank
FROM marts.fact_sales f
INNER JOIN marts.dim_product dp ON dp.upc = f.upc
WHERE f.hhs > 0
GROUP BY dp.description, dp.category, dp.manufacturer
ORDER BY units_per_hh DESC;

-- ============================================================
-- Business Recommendation:
--   1. Protect A-class products (top 70% revenue) — never out of stock.
--   2. Review C-class products for range rationalization.
--   3. Products with high promo_rate and low total_revenue indicate
--      promotion dependency — potential margin leakage risk.
--   4. Declining products (S7) should be reviewed for price repositioning
--      before discontinuation.
--
-- Interview Questions:
--   Q: What is the difference between RANK and DENSE_RANK?
--   A: RANK() leaves gaps after ties (1,2,2,4). DENSE_RANK()
--      does not leave gaps (1,2,2,3). For leaderboards where
--      skipping a position feels unnatural, use DENSE_RANK.
--
--   Q: How would you implement Pareto Analysis in SQL?
--   A: Cumulative SUM() OVER (ORDER BY revenue DESC) / grand_total
--      gives cumulative %. Filter or CASE WHEN on 0.80 threshold.
-- ============================================================
