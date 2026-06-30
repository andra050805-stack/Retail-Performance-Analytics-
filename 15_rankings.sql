-- ============================================================
-- 15_rankings.sql
-- SQL Retail Analytics — Rankings & Percentile Analysis
-- ============================================================
-- Business Objective:
--   Implement comprehensive ranking systems for products,
--   stores, categories, and states. Dynamic rankings that
--   update automatically as data changes — production-ready
--   for leaderboards and executive scorecards.
--
-- Business Questions:
--   Who are the top/bottom performers at every dimension?
--   What percentile does each store/product sit in?
--   How do rankings shift over time?
--
-- SQL Concepts Demonstrated:
--   RANK, DENSE_RANK, ROW_NUMBER, NTILE, PERCENT_RANK,
--   CUME_DIST, percentile_cont, dynamic TOP-N, CTEs
-- ============================================================


-- ============================================================
-- RK1: Multi-Dimensional Product Ranking (Revenue + Units + Promo)
-- ============================================================
-- Business Insight: A product can rank high on revenue but low
--   on units (high price) or vice versa. Composite view helps
--   merchandising teams make balanced decisions.

WITH product_metrics AS (
    SELECT
        dp.upc,
        dp.description,
        dp.category,
        dp.manufacturer,
        ROUND(SUM(f.spend), 2)                          AS total_revenue,
        SUM(f.units)                                    AS total_units,
        ROUND(AVG(f.price), 4)                          AS avg_price,
        ROUND(AVG(f.discount_pct), 2)                   AS avg_discount_pct,
        ROUND(
            SUM(CASE WHEN f.is_promoted THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
        )                                               AS promo_rate_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.upc, dp.description, dp.category, dp.manufacturer
)
SELECT
    description,
    category,
    manufacturer,
    total_revenue,
    total_units,
    avg_price,
    avg_discount_pct,
    promo_rate_pct,

    -- Multiple ranking dimensions
    RANK() OVER (ORDER BY total_revenue DESC)           AS revenue_rank,
    RANK() OVER (ORDER BY total_units DESC)             AS units_rank,
    RANK() OVER (ORDER BY avg_price DESC)               AS price_rank,
    RANK() OVER (ORDER BY avg_discount_pct DESC)        AS discount_rank,
    RANK() OVER (ORDER BY promo_rate_pct DESC)          AS promo_freq_rank,

    -- Within-category rankings
    RANK() OVER (
        PARTITION BY category ORDER BY total_revenue DESC
    )                                                   AS category_revenue_rank,
    RANK() OVER (
        PARTITION BY category ORDER BY total_units DESC
    )                                                   AS category_units_rank,

    -- Percentile rank (0–1 scale): 1.0 = highest
    ROUND(PERCENT_RANK() OVER (ORDER BY total_revenue ASC), 4) AS revenue_percentile,

    -- Cumulative distribution: % of products at or below this revenue
    ROUND(CUME_DIST() OVER (ORDER BY total_revenue ASC), 4)    AS revenue_cume_dist

FROM product_metrics
ORDER BY revenue_rank;


-- ============================================================
-- RK2: Dynamic Top-N by Category (Parameterized)
-- ============================================================
-- Business Use: Top 3 products per category — scalable to any N.
--   Production version would use a parameter or variable for N.

WITH ranked_products AS (
    SELECT
        dp.category,
        dp.description,
        dp.manufacturer,
        ROUND(SUM(f.spend), 2) AS total_revenue,
        SUM(f.units) AS total_units,
        ROUND(AVG(f.price), 4) AS avg_price,
        DENSE_RANK() OVER (
            PARTITION BY dp.category
            ORDER BY SUM(f.spend) DESC
        ) AS cat_rank
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.category, dp.description, dp.manufacturer
)
SELECT
    category,
    cat_rank,
    description,
    manufacturer,
    total_revenue,
    total_units,
    avg_price
FROM ranked_products
WHERE cat_rank <= 3      -- Change this to get Top-N
ORDER BY category, cat_rank;


-- ============================================================
-- RK3: Store Ranking by State — Best Store in Each State
-- ============================================================
-- Business Insight: Regional performance champion — useful for
--   "Star Store" recognition programs and regional benchmarking.

WITH state_store_rank AS (
    SELECT
        ds.state,
        ds.store_num,
        ds.store_name,
        ds.seg_value_name,
        ROUND(SUM(f.spend), 2)  AS total_revenue,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value,
        RANK() OVER (
            PARTITION BY ds.state
            ORDER BY SUM(f.spend) DESC
        ) AS state_rank
    FROM marts.fact_sales f
    INNER JOIN marts.dim_store ds ON ds.store_num = f.store_num
    GROUP BY ds.state, ds.store_num, ds.store_name, ds.seg_value_name
)
SELECT
    state,
    state_rank,
    store_num,
    store_name,
    seg_value_name,
    total_revenue,
    avg_basket_value,
    CASE state_rank
        WHEN 1 THEN '🏆 State Champion'
        WHEN 2 THEN '🥈 Runner-Up'
        WHEN 3 THEN '🥉 Third Place'
        ELSE        'Ranked ' || state_rank
    END AS state_standing
FROM state_store_rank
WHERE state_rank <= 3
ORDER BY state, state_rank;


-- ============================================================
-- RK4: Revenue Percentile Buckets (Decile Analysis)
-- ============================================================
-- Business Insight: Segment all 58 products into 10 deciles.
--   Decile 1 = top 10% of revenue generators.
--   Decile 10 = bottom 10% — tail SKU candidates.

WITH product_deciles AS (
    SELECT
        dp.upc,
        dp.description,
        dp.category,
        ROUND(SUM(f.spend), 2) AS total_revenue,
        NTILE(10) OVER (ORDER BY SUM(f.spend) DESC) AS decile,
        ROUND(PERCENT_RANK() OVER (ORDER BY SUM(f.spend) ASC) * 100, 2) AS percentile
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.upc, dp.description, dp.category
)
SELECT
    decile,
    COUNT(*)                        AS products_in_decile,
    ROUND(MIN(total_revenue), 2)    AS min_revenue,
    ROUND(MAX(total_revenue), 2)    AS max_revenue,
    ROUND(AVG(total_revenue), 2)    AS avg_revenue,
    ROUND(SUM(total_revenue), 2)    AS decile_total_revenue,
    ROUND(
        SUM(total_revenue) * 100.0 / SUM(SUM(total_revenue)) OVER (), 2
    )                               AS pct_of_portfolio_revenue,
    STRING_AGG(description, ', ' ORDER BY total_revenue DESC) AS products
FROM product_deciles
GROUP BY decile
ORDER BY decile;


-- ============================================================
-- RK5: Ranking Shift Over Time (Year-over-Year Rank Change)
-- ============================================================
-- Business Insight: Did this product rise or fall in rank?
--   Rank movement reveals competitive dynamics and growth
--   trajectory — essential for portfolio strategy reviews.

WITH yearly_product_rev AS (
    SELECT
        dc.year,
        dp.upc,
        dp.description,
        dp.category,
        ROUND(SUM(f.spend), 2) AS annual_revenue,
        RANK() OVER (
            PARTITION BY dc.year
            ORDER BY SUM(f.spend) DESC
        ) AS yearly_rank
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY dc.year, dp.upc, dp.description, dp.category
)
SELECT
    curr.year,
    curr.upc,
    curr.description,
    curr.category,
    curr.annual_revenue,
    curr.yearly_rank                AS current_rank,
    prev.yearly_rank                AS prior_year_rank,
    -- Positive = improved (rank number went down); negative = declined
    COALESCE(prev.yearly_rank - curr.yearly_rank, 0) AS rank_change,
    CASE
        WHEN prev.yearly_rank IS NULL                        THEN '🆕 NEW ENTRY'
        WHEN curr.yearly_rank < prev.yearly_rank             THEN '▲ RISING'
        WHEN curr.yearly_rank > prev.yearly_rank             THEN '▼ FALLING'
        ELSE                                                      '─ STABLE'
    END AS trend_direction
FROM yearly_product_rev curr
LEFT JOIN yearly_product_rev prev
    ON prev.upc = curr.upc
    AND prev.year = curr.year - 1
ORDER BY curr.year, curr.yearly_rank;


-- ============================================================
-- RK6: Percentile-Based Discount Depth Ranking
-- ============================================================
-- Business Insight: Rank products by how aggressively they
--   are discounted, expressed as a percentile. High percentile
--   = this product is discounted more than X% of the portfolio.

WITH discount_metrics AS (
    SELECT
        dp.upc,
        dp.description,
        dp.category,
        ROUND(AVG(f.discount_pct), 4)   AS avg_discount_pct,
        ROUND(MAX(f.discount_pct), 4)   AS max_discount_pct,
        SUM(CASE WHEN f.discount_pct > 0 THEN 1 ELSE 0 END) AS discounted_rows,
        COUNT(*)                         AS total_rows
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.upc, dp.description, dp.category
)
SELECT
    description,
    category,
    avg_discount_pct,
    max_discount_pct,
    ROUND(discounted_rows * 100.0 / total_rows, 2) AS pct_rows_discounted,
    RANK() OVER (ORDER BY avg_discount_pct DESC)    AS discount_rank,
    ROUND(
        PERCENT_RANK() OVER (ORDER BY avg_discount_pct ASC) * 100, 2
    )                                               AS discount_percentile,
    ROUND(
        CUME_DIST() OVER (ORDER BY avg_discount_pct ASC) * 100, 2
    )                                               AS discount_cume_dist_pct
FROM discount_metrics
ORDER BY avg_discount_pct DESC;


-- ============================================================
-- RK7: Store Segment Rank Within Global Portfolio
-- ============================================================
-- Business Insight: Global store rank (1–79) alongside
--   within-segment rank and segment percentile.
--   Helps identify which stores are segment leaders
--   vs portfolio leaders — they may differ.

WITH store_perf AS (
    SELECT
        f.store_num,
        ROUND(SUM(f.spend), 2)  AS total_revenue,
        ROUND(SUM(f.spend) / NULLIF(SUM(f.visits), 0), 4) AS avg_basket_value
    FROM marts.fact_sales f
    GROUP BY f.store_num
)
SELECT
    sp.store_num,
    ds.store_name,
    ds.seg_value_name,
    ds.state,
    sp.total_revenue,
    sp.avg_basket_value,

    -- Global rank
    RANK() OVER (ORDER BY sp.total_revenue DESC)        AS global_rank,

    -- Segment rank
    RANK() OVER (
        PARTITION BY ds.seg_value_name
        ORDER BY sp.total_revenue DESC
    )                                                   AS segment_rank,

    -- State rank
    RANK() OVER (
        PARTITION BY ds.state
        ORDER BY sp.total_revenue DESC
    )                                                   AS state_rank,

    -- Global percentile (0–100)
    ROUND(
        PERCENT_RANK() OVER (ORDER BY sp.total_revenue ASC) * 100, 1
    )                                                   AS global_percentile,

    -- Segment percentile
    ROUND(
        PERCENT_RANK() OVER (
            PARTITION BY ds.seg_value_name
            ORDER BY sp.total_revenue ASC
        ) * 100, 1
    )                                                   AS segment_percentile
FROM store_perf sp
INNER JOIN marts.dim_store ds ON ds.store_num = sp.store_num
ORDER BY global_rank;

-- ============================================================
-- Interview Questions:
--   Q: What is PERCENT_RANK vs CUME_DIST?
--   A: PERCENT_RANK = (rank - 1) / (total_rows - 1). Range 0–1.
--      0 = lowest, 1 = highest. CUME_DIST = rows at or below /
--      total rows. Always > 0. Use CUME_DIST for "what % of items
--      are at or below this value?" Use PERCENT_RANK for strict
--      relative position excluding self.
--
--   Q: When do you use RANK vs DENSE_RANK vs ROW_NUMBER?
--   A: RANK: gaps after ties (competition-style: 1,2,2,4).
--      DENSE_RANK: no gaps (1,2,2,3). Preferred for top-N filters.
--      ROW_NUMBER: always unique (1,2,3,4). Use for deduplication.
-- ============================================================
