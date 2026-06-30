# 🛒 SQL Retail Analytics Portfolio
### Dunnhumby "Breakfast at the Frat" — Production-Grade Analytics Repository

---

## 📋 Project Overview

This repository demonstrates a **production-level SQL analytics engineering workflow** built on the Dunnhumby "Breakfast at the Frat" retail dataset. It translates a comprehensive Machine Learning project into a complete data warehouse ecosystem — from raw data validation through executive dashboards — using advanced SQL techniques aligned with modern analytics engineering best practices (dbt, Snowflake, BigQuery, PostgreSQL).

The analytical narrative answers five core business questions:
1. **Pricing** — Where is margin lost, and which price points maximize revenue?
2. **Promotion** — Which promotional levers (Feature, Display, TPR) drive the most incremental volume?
3. **Store Performance** — How do Upscale, Mainstream, and Value segments differ in basket behavior?
4. **Product Strategy** — Which products carry the portfolio, and which underperform?
5. **Customer Behavior** — How do households engage across categories and store types?

---

## 🗄️ Dataset Description

| Table | Rows | Description |
|---|---|---|
| `dh_transaction_data` | 524,950 | Weekly sales by store × UPC |
| `dh_product_lookup` | 58 | Product master (category, manufacturer, size) |
| `dh_store_lookup` | 79 | Store master (state, segment, parking, sqft) |

**Coverage:** 156 weeks · 4 categories · 79 stores · 18 states

**Categories:** Mouthwash · Pretzels · Frozen Pizza · Boxed Cereal

---

## 🗺️ Database Schema (Star Schema)

```
                    ┌─────────────────┐
                    │   dim_calendar  │
                    │─────────────────│
                    │ date_key (PK)   │
                    │ week_end_date   │
                    │ year            │
                    │ quarter         │
                    │ month           │
                    │ week_num        │
                    └────────┬────────┘
                             │
┌────────────────┐    ┌──────┴──────────┐    ┌────────────────┐
│  dim_product   │    │   fact_sales    │    │   dim_store    │
│────────────────│    │─────────────────│    │────────────────│
│ upc (PK)       ├────┤ upc (FK)        ├────┤ store_num (PK) │
│ description    │    │ store_num (FK)  │    │ state          │
│ category       │    │ date_key (FK)   │    │ city           │
│ sub_category   │    │ units           │    │ seg_value_name │
│ manufacturer   │    │ visits          │    │ sales_area_sqft│
│ product_size   │    │ hhs             │    │ parking_spaces │
└────────────────┘    │ spend           │    │ avg_wkly_bskts │
                      │ price           │    └────────────────┘
                      │ base_price      │
                      │ feature         │
                      │ display         │
                      │ tpr_only        │
                      └─────────────────┘
```

---

## 📐 Entity Relationship Diagram (ERD)

```
dh_product_lookup ──< dh_transaction_data >── dh_store_lookup
      UPC (PK)            UPC (FK)                 STORE_NUM (PK)
                          STORE_NUM (FK)
                          WEEK_END_DATE
```

**Relationships:**
- One product → Many transactions (1:N via UPC)
- One store → Many transactions (1:N via STORE_NUM)
- One week → Many transactions (1:N via WEEK_END_DATE)

---

## 🏗️ Analytics Architecture

```
Raw Layer          → Raw tables as loaded (dh_transaction_data, dh_product_lookup, dh_store_lookup)
Staging Layer      → 01_data_validation.sql, 02_data_cleaning.sql
Intermediate Layer → 03_dimension_tables.sql, 04_fact_tables.sql
Mart Layer         → 05–16 (business metrics, analysis, segmentation)
Reporting Layer    → 17_kpi_dashboard.sql, 18_advanced_business_questions.sql
Presentation Layer → 19_views.sql, 20_final_report.sql
```

---

## 📁 Repository Structure

```
SQL_Retail_Analytics/
│
├── README.md                           ← You are here
├── schema.sql                          ← DDL: all table definitions
├── data_dictionary.md                  ← Field-level documentation
│
├── 01_data_validation.sql              ← Null checks, range checks, duplicate checks
├── 02_data_cleaning.sql                ← Imputation, deduplication, outlier flags
├── 03_dimension_tables.sql             ← dim_product, dim_store, dim_calendar
├── 04_fact_tables.sql                  ← fact_sales + aggregate fact tables
├── 05_business_metrics.sql             ← Core KPIs: revenue, units, basket metrics
├── 06_sales_analysis.sql               ← Weekly/monthly/quarterly trend analysis
├── 07_product_analysis.sql             ← Product ranking, ABC, Pareto
├── 08_store_analysis.sql               ← Store performance, segment comparison
├── 09_pricing_analysis.sql             ← Price bands, discount depth, elasticity proxy
├── 10_promotion_analysis.sql           ← Promo lift, display/feature/TPR effects
├── 11_customer_behavior.sql            ← Basket metrics, HH behavior, intensity
├── 12_time_series.sql                  ← Seasonality, weekly trends, YoY
├── 13_window_functions.sql             ← Running totals, rolling averages, LAG/LEAD
├── 14_cte_queries.sql                  ← Complex multi-step CTE analyses
├── 15_rankings.sql                     ← Dynamic ranking, NTILE, percentile
├── 16_segmentation.sql                 ← ABC classification, store/product segments
├── 17_kpi_dashboard.sql                ← Executive single-query dashboard
├── 18_advanced_business_questions.sql  ← Deep-dive analytical questions
├── 19_views.sql                        ← Reusable views and materialized view specs
└── 20_final_report.sql                 ← Narrative-driven final executive report
```

---

## 🔧 SQL Skills Demonstrated

| Category | Techniques |
|---|---|
| **Joins** | INNER, LEFT, RIGHT, FULL OUTER, SELF, CROSS |
| **Set Operations** | UNION, UNION ALL |
| **Aggregation** | GROUP BY, HAVING, ROLLUP, CUBE |
| **Subqueries** | Correlated subqueries, scalar subqueries, inline views |
| **CTEs** | Linear chains, multi-branch, recursive |
| **Window Functions** | ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD, FIRST_VALUE, LAST_VALUE |
| **Window Frames** | Running totals, rolling 4-week, rolling 12-week, cumulative |
| **Date Functions** | EXTRACT, DATE_TRUNC, DATE_DIFF, DATEADD |
| **String Functions** | CONCAT, UPPER, TRIM, SPLIT_PART |
| **Conditional** | CASE WHEN, COALESCE, NULLIF, IIF |
| **Type Casting** | CAST, TRY_CAST |
| **Performance** | Index recommendations, materialized views, partitioning |
| **DDL** | CREATE TABLE, CREATE VIEW, CREATE INDEX, CREATE MATERIALIZED VIEW |

---

## 💼 Business Questions Answered

- What is the total revenue and units by category, product, store, and state?
- Which promotional strategy (Feature vs Display vs TPR vs Combined) generates the highest sales lift?
- What is the price elasticity approximation per product category?
- Which stores are in the Top 10% by revenue per square foot?
- What is the 12-week rolling average revenue trend across all categories?
- How does store segment (Upscale/Mainstream/Value) affect basket size and revenue per household?
- Which 20% of products drive 80% of revenue (Pareto Analysis)?
- What is the ABC classification of products by revenue contribution?
- How do promotional weeks compare to baseline weeks in units, spend, and visits?
- What is the discount depth required to achieve meaningful volume uplift?
- What is the YoY revenue growth trend?
- Which products and stores have declining sales trajectories?

---

## 📊 Sample Results

| Metric | Value |
|---|---|
| Total Revenue (156 weeks) | ~$17.6M |
| Total Units | ~5.1M |
| Total HH Visits | ~5.4M |
| Avg Basket Value | ~$3.74 |
| Avg Discount | ~5.7% |
| Promo Rate | ~25% of weeks |
| Top Category | Cereal |
| Best Segment | Upscale |

---

## ⚡ Performance Optimization

- **Partitioning:** `fact_sales` partitioned by `week_end_date` (weekly grain)
- **Clustering:** Cluster on `upc`, `store_num` for common filter patterns
- **Indexes:** Composite indexes on `(store_num, upc)`, `(week_end_date, category)`
- **Materialized Views:** Pre-aggregated weekly summaries for dashboard queries
- **CTEs vs Subqueries:** CTEs preferred for readability and optimizer hints

---

## 🎯 Key Business Insights

1. **Combined promotions (Feature + Display + TPR) produce 3–5× baseline unit volume** — but margin impact must be weighed against frequency.
2. **Top 20% of products account for ~80% of revenue** — classic Pareto holds in this dataset.
3. **Upscale store segment shows higher basket value** but similar units per visit to Mainstream.
4. **Avg discount of ~5.7%** is modest — many zero-discount weeks drag the mean; promotional weeks average 15–25% off.
5. **Cereal and Frozen Pizza are volume leaders**; Mouthwash shows higher price per unit.
6. **Optimal price point ~$3.29** for the overall portfolio to maximize predicted revenue (from ML layer).

---

## 📝 Resume-Ready Project Summary

> **SQL Retail Analytics Portfolio** | Analytics Engineering · Business Intelligence · Data Warehousing
>
> Designed and implemented a production-grade SQL analytics repository on the Dunnhumby "Breakfast at the Frat" retail dataset (525K rows, 3 relational tables). Built a complete layered data warehouse: staging → dimensions → facts → marts → dashboards. Demonstrated mastery of advanced SQL including window functions (LAG/LEAD, rolling aggregates), CTEs, correlated subqueries, UNION operations, star schema design, index optimization, and materialized view strategy. Answered 50+ business questions covering pricing analytics, promotion lift measurement, store segmentation, ABC classification, Pareto analysis, and executive KPI dashboards. Portfolio demonstrates competencies aligned with Analytics Engineer / BI Engineer / Senior Data Analyst roles at FAANG and leading Southeast Asian tech companies.

---

## 🔮 Future Improvements

- Integrate with dbt to transform raw SQL into modular, tested models
- Add Python/Jinja templating for dynamic date filtering
- Build Looker or Metabase dashboard on top of the view layer
- Add `mart_pricing_simulation` table for what-if scenario outputs
- Implement row-level security for multi-tenant store access

---

*Built by: Andraneta | Actuarial Science, Institut Teknologi Bandung*
*Dataset: Dunnhumby "Breakfast at the Frat" | © 2023 dunnhumby*
