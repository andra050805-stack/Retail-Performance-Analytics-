-- ============================================================
-- 18_advanced_business_questions.sql
-- SQL Retail Analytics — Advanced Business Questions
-- ============================================================
-- Business Objective:
--   Answer the hardest analytical questions that combine
--   multiple SQL techniques into cohesive business narratives.
--   Each query is designed to impress senior Analytics Engineers
--   and Data Leaders in interviews.
--
-- SQL Concepts Demonstrated:
--   Complex CTEs, correlated subqueries, multiple JOINs,
--   CASE WHEN logic, window + aggregate combination,
--   FULL OUTER JOIN, SELF JOIN, recursive patterns
-- ============================================================


-- ============================================================
-- ABQ1: Which products are "Promoted Champions" vs "True Champions"?
-- ============================================================
-- Business Insight: A product that only sells well during
--   promotions is not a true champion — it's promo-dependent.
--   Products with high baseline + high promo = True Champion.
--   Aligned with notebook Chapter 7 + 10 synthesis.

WITH product_split AS (
    SELECT
        dp.upc,
        dp.description,
        dp.category,
        dp.manufacturer,
        -- Revenue split
        ROUND(SUM(CASE WHEN f.is_promoted THEN f.spend ELSE 0 END), 2) AS promo_revenue,
        ROUND(SUM(CASE WHEN NOT f.is_promoted THEN f.spend ELSE 0 END), 2) AS baseline_revenue,
        ROUND(SUM(f.spend), 2) AS total_revenue,
        -- Unit split
        SUM(CASE WHEN f.is_promoted THEN f.units ELSE 0 END) AS promo_units,
        SUM(CASE WHEN NOT f.is_promoted THEN f.units ELSE 0 END) AS baseline_units,
        -- Promo frequency
        ROUND(SUM(CASE WHEN f.is_promoted THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 2) AS promo_rate_pct
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.upc, dp.description, dp.category, dp.manufacturer
),
-- Get revenue medians for classification
medians AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_revenue) AS median_total_rev,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY baseline_revenue) AS median_baseline_rev
    FROM product_split
)
SELECT
    ps.upc,
    ps.description,
    ps.category,
    ps.manufacturer,
    ps.promo_revenue,
    ps.baseline_revenue,
    ps.total_revenue,
    ps.promo_rate_pct,
    ROUND(ps.promo_revenue / NULLIF(ps.total_revenue, 0) * 100, 2) AS promo_revenue_share_pct,
    CASE
        WHEN ps.baseline_revenue >= m.median_baseline_rev
             AND ps.total_revenue >= m.median_total_rev
             AND ps.promo_rate_pct < 30
             THEN '🏆 TRUE CHAMPION — High baseline, low promo need'
        WHEN ps.total_revenue >= m.median_total_rev
             AND ps.promo_rate_pct >= 30
             THEN '🎯 PROMO CHAMPION — Only shines during deals'
        WHEN ps.baseline_revenue >= m.median_baseline_rev
             AND ps.total_revenue < m.median_total_rev
             THEN '💎 SLEEPER — Good baseline, low total volume'
        ELSE      '⚠️ STRUGGLER — Below average on both dimensions'
    END AS champion_class
FROM product_split ps
CROSS JOIN medians m
ORDER BY ps.total_revenue DESC;


-- ============================================================
-- ABQ2: Store × Category Opportunity Matrix
-- ============================================================
-- Business Insight: For each store × category combination,
--   compare actual revenue to the average store's performance
--   in that category. Underperformance = untapped potential.
--   FULL OUTER JOIN to catch any orphan combinations.

WITH actual AS (
    SELECT
        f.store_num,
        dp.category,
        ROUND(SUM(f.spend), 2) AS actual_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY f.store_num, dp.category
),
avg_by_cat AS (
    SELECT
        category,
        ROUND(AVG(actual_revenue), 2) AS avg_store_category_revenue
    FROM actual
    GROUP BY category
)
SELECT
    a.store_num,
    ds.store_name,
    ds.seg_value_name,
    a.category,
    a.actual_revenue,
    avg.avg_store_category_revenue,
    ROUND(a.actual_revenue - avg.avg_store_category_revenue, 2) AS vs_avg_delta,
    ROUND(
        (a.actual_revenue - avg.avg_store_category_revenue)
        / NULLIF(avg.avg_store_category_revenue, 0) * 100, 2
    ) AS vs_avg_pct,
    CASE
        WHEN a.actual_revenue >= avg.avg_store_category_revenue * 1.2 THEN '🟢 Outperformer (+20%+)'
        WHEN a.actual_revenue >= avg.avg_store_category_revenue * 0.8 THEN '🟡 On Track (±20%)'
        ELSE                                                                '🔴 Underperformer (-20%+)'
    END AS performance_flag
FROM actual a
INNER JOIN avg_by_cat avg ON avg.category = a.category
INNER JOIN marts.dim_store ds ON ds.store_num = a.store_num
ORDER BY vs_avg_pct ASC;   -- Show biggest underperformers first


-- ============================================================
-- ABQ3: Price Gap Analysis — When Does Competitor Pricing Change Demand?
-- ============================================================
-- Business Insight: Within a category, how does the price gap
--   between products affect their relative unit performance?
--   Simulates competitive price-gap dynamics from notebook Ch.9.

WITH cat_weekly AS (
    SELECT
        f.date_key,
        f.store_num,
        dp.category,
        dp.description,
        ROUND(AVG(f.price), 4)  AS avg_price,
        SUM(f.units)            AS total_units,
        dp.upc
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY f.date_key, f.store_num, dp.category, dp.description, dp.upc
),
-- Self-join to compare every product pair within same category-store-week
price_pairs AS (
    SELECT
        a.date_key,
        a.store_num,
        a.category,
        a.description     AS product_a,
        b.description     AS product_b,
        a.avg_price       AS price_a,
        b.avg_price       AS price_b,
        ROUND(a.avg_price - b.avg_price, 4) AS price_gap,
        a.total_units     AS units_a,
        b.total_units     AS units_b
    FROM cat_weekly a
    INNER JOIN cat_weekly b
        ON a.date_key = b.date_key
        AND a.store_num = b.store_num
        AND a.category = b.category
        AND a.upc < b.upc    -- Avoid duplicates
)
SELECT
    category,
    product_a,
    product_b,
    COUNT(*)                        AS weeks_compared,
    ROUND(AVG(price_gap), 4)        AS avg_price_gap,
    ROUND(AVG(units_a), 2)          AS avg_units_a,
    ROUND(AVG(units_b), 2)          AS avg_units_b,
    -- Which product wins more weeks?
    SUM(CASE WHEN units_a > units_b THEN 1 ELSE 0 END) AS weeks_a_wins,
    SUM(CASE WHEN units_b > units_a THEN 1 ELSE 0 END) AS weeks_b_wins,
    -- Correlation proxy: when price gap widens, does lower-price product gain share?
    ROUND(CORR(price_gap, units_a - units_b), 4) AS gap_unit_correlation
FROM price_pairs
GROUP BY category, product_a, product_b
HAVING COUNT(*) > 10    -- Only pairs with sufficient data
ORDER BY category, ABS(ROUND(CORR(price_gap, units_a - units_b), 4)) DESC;


-- ============================================================
-- ABQ4: Cohort-Style Analysis — Stores by Launch Quarter
-- ============================================================
-- Business Insight: Simulate cohort analysis by grouping stores
--   by their first observed selling quarter. How does revenue
--   trajectory differ between early vs late cohorts?

WITH store_first_quarter AS (
    SELECT
        f.store_num,
        MIN(dc.year * 10 + dc.quarter) AS first_year_quarter
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY f.store_num
),
store_cohort AS (
    SELECT
        s.store_num,
        CASE
            WHEN s.first_year_quarter <= (SELECT MIN(first_year_quarter) FROM store_first_quarter) + 1
            THEN 'EARLY COHORT'
            ELSE 'LATER COHORT'
        END AS cohort
    FROM store_first_quarter s
),
cohort_quarterly AS (
    SELECT
        sc.cohort,
        dc.year,
        dc.quarter,
        ROUND(SUM(f.spend), 2)  AS quarterly_revenue,
        COUNT(DISTINCT f.store_num) AS active_stores,
        ROUND(SUM(f.spend) / COUNT(DISTINCT f.store_num), 2) AS revenue_per_store
    FROM marts.fact_sales f
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    INNER JOIN store_cohort sc ON sc.store_num = f.store_num
    GROUP BY sc.cohort, dc.year, dc.quarter
)
SELECT
    cohort,
    year,
    quarter,
    active_stores,
    quarterly_revenue,
    revenue_per_store,
    LAG(revenue_per_store) OVER (
        PARTITION BY cohort ORDER BY year, quarter
    ) AS prior_quarter_rps,
    ROUND(
        (revenue_per_store - LAG(revenue_per_store) OVER (
            PARTITION BY cohort ORDER BY year, quarter
        )) / NULLIF(LAG(revenue_per_store) OVER (
            PARTITION BY cohort ORDER BY year, quarter
        ), 0) * 100, 2
    ) AS qoq_rps_growth_pct
FROM cohort_quarterly
ORDER BY cohort, year, quarter;


-- ============================================================
-- ABQ5: Promotion ROI with Volume-Adjusted Margin Impact
-- ============================================================
-- Business Insight: Deep-dive on whether promotions are net
--   positive for the business. Combines promo lift with
--   estimated margin cost (using discount as margin proxy).

WITH promo_impact AS (
    SELECT
        dp.category,
        dp.description,
        f.promo_type,

        -- Volume metrics
        ROUND(AVG(f.units), 2)                  AS avg_units,
        ROUND(AVG(f.spend), 4)                  AS avg_revenue,

        -- Margin proxy (using discount as cost)
        ROUND(AVG(f.discount_pct), 2)           AS avg_discount_pct,

        -- Foregone revenue per row
        ROUND(AVG(f.price_gap * f.units), 4)   AS avg_foregone_revenue,

        COUNT(*)                                AS row_count
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    GROUP BY dp.category, dp.description, f.promo_type
),
pivot_promo AS (
    SELECT
        category,
        description,
        MAX(CASE WHEN promo_type = 'NONE'     THEN avg_units    END) AS baseline_units,
        MAX(CASE WHEN promo_type = 'NONE'     THEN avg_revenue  END) AS baseline_revenue,
        MAX(CASE WHEN promo_type = 'COMBINED' THEN avg_units    END) AS combined_units,
        MAX(CASE WHEN promo_type = 'COMBINED' THEN avg_revenue  END) AS combined_revenue,
        MAX(CASE WHEN promo_type = 'COMBINED' THEN avg_foregone_revenue END) AS combined_foregone_rev,
        MAX(CASE WHEN promo_type = 'COMBINED' THEN avg_discount_pct END) AS combined_discount
    FROM promo_impact
    GROUP BY category, description
)
SELECT
    category,
    description,
    baseline_units,
    combined_units,
    ROUND((combined_units - baseline_units) / NULLIF(baseline_units, 0) * 100, 2) AS unit_lift_pct,
    baseline_revenue,
    combined_revenue,
    combined_foregone_rev,
    ROUND(combined_revenue - combined_foregone_rev, 4)                           AS net_revenue,
    ROUND((combined_revenue - combined_foregone_rev) / NULLIF(combined_revenue, 0) * 100, 2) AS net_margin_pct,
    CASE
        WHEN (combined_revenue - combined_foregone_rev) > baseline_revenue THEN '✅ POSITIVE ROI'
        ELSE '❌ NEGATIVE ROI — Discount costs exceed incremental revenue'
    END AS roi_verdict
FROM pivot_promo
WHERE baseline_units IS NOT NULL AND combined_units IS NOT NULL
ORDER BY net_margin_pct DESC;


-- ============================================================
-- ABQ6: "Dead Zones" — Store-Category Pairs with Zero Growth
-- ============================================================
-- Business Insight: Identify store-category combinations where
--   revenue has been flat or declining for 3+ consecutive quarters.
--   These are commercial blind spots needing intervention.

WITH qtr_revenue AS (
    SELECT
        f.store_num,
        dp.category,
        dc.year,
        dc.quarter,
        ROUND(SUM(f.spend), 2) AS qtr_revenue
    FROM marts.fact_sales f
    INNER JOIN marts.dim_product dp ON dp.upc = f.upc
    INNER JOIN marts.dim_calendar dc ON dc.date_key = f.date_key
    GROUP BY f.store_num, dp.category, dc.year, dc.quarter
),
with_growth AS (
    SELECT
        store_num,
        category,
        year,
        quarter,
        qtr_revenue,
        LAG(qtr_revenue) OVER (
            PARTITION BY store_num, category ORDER BY year, quarter
        ) AS prev_qtr_revenue,
        CASE
            WHEN qtr_revenue <= LAG(qtr_revenue) OVER (
                PARTITION BY store_num, category ORDER BY year, quarter
            ) THEN 1 ELSE 0
        END AS is_flat_or_declining
    FROM qtr_revenue
),
consecutive_count AS (
    SELECT
        store_num,
        category,
        year,
        quarter,
        qtr_revenue,
        is_flat_or_declining,
        SUM(is_flat_or_declining) OVER (
            PARTITION BY store_num, category
            ORDER BY year, quarter
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS consec_flat_qtrs
    FROM with_growth
)
SELECT
    cc.store_num,
    ds.store_name,
    ds.seg_value_name,
    cc.category,
    cc.year,
    cc.quarter,
    cc.qtr_revenue,
    cc.consec_flat_qtrs,
    '⚠️ DEAD ZONE — 3+ Quarters Flat/Declining' AS alert
FROM consecutive_count cc
INNER JOIN marts.dim_store ds ON ds.store_num = cc.store_num
WHERE cc.consec_flat_qtrs = 3
ORDER BY cc.store_num, cc.category, cc.year, cc.quarter;

-- ============================================================
-- Interview Questions:
--   Q: How do you identify N consecutive periods of decline?
--   A: SUM(decline_flag) OVER (ORDER BY date ROWS BETWEEN N-1
--      PRECEDING AND CURRENT ROW) = N means all N periods declined.
--      This uses a rolling count of a binary flag.
--
--   Q: What is a SELF JOIN and when do you use it?
--   A: A table joined to itself. Common uses: find pairs within
--      a group (e.g., product price comparisons within category),
--      compare a row to its predecessor, or find hierarchy paths.
-- ============================================================
