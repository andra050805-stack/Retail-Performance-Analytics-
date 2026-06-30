-- ============================================================
-- schema.sql
-- SQL Retail Analytics — Full Schema Definition
-- Dataset: Dunnhumby "Breakfast at the Frat"
-- Target Platforms: Snowflake / BigQuery / PostgreSQL
-- ============================================================
-- Business Objective:
--   Define the complete relational schema for the retail
--   analytics data warehouse, from raw source tables through
--   the dimensional star schema layer and aggregate marts.
-- ============================================================

-- ============================================================
-- 0. SCHEMA / DATABASE SETUP
-- ============================================================

-- Snowflake
-- CREATE DATABASE IF NOT EXISTS retail_analytics;
-- CREATE SCHEMA IF NOT EXISTS retail_analytics.raw;
-- CREATE SCHEMA IF NOT EXISTS retail_analytics.staging;
-- CREATE SCHEMA IF NOT EXISTS retail_analytics.marts;

-- PostgreSQL
-- CREATE SCHEMA IF NOT EXISTS raw;
-- CREATE SCHEMA IF NOT EXISTS staging;
-- CREATE SCHEMA IF NOT EXISTS marts;


-- ============================================================
-- 1. RAW LAYER — Source Tables (as ingested from xlsx)
-- ============================================================

-- 1a. Raw Transaction Data
CREATE TABLE IF NOT EXISTS raw.dh_transaction_data (
    week_end_date   DATE            NOT NULL,
    store_num       INTEGER         NOT NULL,
    upc             BIGINT          NOT NULL,
    units           INTEGER,
    visits          INTEGER,
    hhs             INTEGER,
    spend           NUMERIC(12, 4),
    price           NUMERIC(10, 4),
    base_price      NUMERIC(10, 4),
    feature         SMALLINT        DEFAULT 0,
    display         SMALLINT        DEFAULT 0,
    tpr_only        SMALLINT        DEFAULT 0,
    -- Audit columns
    _loaded_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE raw.dh_transaction_data IS
    'Raw weekly retail transaction data: 524,950 rows, 156 weeks, 79 stores, 58 products.';

COMMENT ON COLUMN raw.dh_transaction_data.spend IS
    'Total dollar revenue (units × actual shelf price). May be 0 for data quality issues.';
COMMENT ON COLUMN raw.dh_transaction_data.price IS
    'Actual shelf price charged to consumer that week.';
COMMENT ON COLUMN raw.dh_transaction_data.base_price IS
    'Regular (non-promotional) reference price.';
COMMENT ON COLUMN raw.dh_transaction_data.feature IS
    '1 = product featured in in-store circular; 0 = not.';
COMMENT ON COLUMN raw.dh_transaction_data.display IS
    '1 = product on in-store display; 0 = not.';
COMMENT ON COLUMN raw.dh_transaction_data.tpr_only IS
    '1 = temporary price reduction via shelf tag only (no display/feature); 0 = not.';


-- 1b. Raw Product Lookup
CREATE TABLE IF NOT EXISTS raw.dh_product_lookup (
    upc             BIGINT          NOT NULL,
    category        VARCHAR(100),
    description     VARCHAR(255),
    manufacturer    VARCHAR(100),
    sub_category    VARCHAR(100),
    product_size    VARCHAR(50),
    _loaded_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE raw.dh_product_lookup IS
    'Product master: 58 unique UPCs across 4 categories (Mouthwash, Pretzels, Frozen Pizza, Cereal).';


-- 1c. Raw Store Lookup
CREATE TABLE IF NOT EXISTS raw.dh_store_lookup (
    store_num               INTEGER         NOT NULL,
    store_name              VARCHAR(100),
    address_city_name       VARCHAR(100),
    address_state_prov_code VARCHAR(10),
    msa_code                INTEGER,
    seg_value_name          VARCHAR(50),
    parking_space_qty       NUMERIC(8, 2),
    sales_area_size_num     INTEGER,
    avg_weekly_baskets      NUMERIC(12, 2),
    _loaded_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE raw.dh_store_lookup IS
    '79 stores across multiple US states. SEG_VALUE_NAME: Upscale / Mainstream / Value.';
COMMENT ON COLUMN raw.dh_store_lookup.seg_value_name IS
    'Store price positioning segment: Value, Mainstream, or Upscale.';
COMMENT ON COLUMN raw.dh_store_lookup.avg_weekly_baskets IS
    'Average number of customer baskets per week — measure of store traffic volume.';


-- ============================================================
-- 2. STAGING LAYER — Cleaned & Validated Tables
-- ============================================================

CREATE TABLE IF NOT EXISTS staging.stg_transactions (
    week_end_date       DATE            NOT NULL,
    store_num           INTEGER         NOT NULL,
    upc                 BIGINT          NOT NULL,
    units               INTEGER         NOT NULL    DEFAULT 0,
    visits              INTEGER         NOT NULL    DEFAULT 0,
    hhs                 INTEGER         NOT NULL    DEFAULT 0,
    spend               NUMERIC(12, 4)  NOT NULL    DEFAULT 0,
    price               NUMERIC(10, 4)  NOT NULL,
    base_price          NUMERIC(10, 4)  NOT NULL,
    feature             SMALLINT        NOT NULL    DEFAULT 0,
    display             SMALLINT        NOT NULL    DEFAULT 0,
    tpr_only            SMALLINT        NOT NULL    DEFAULT 0,
    -- Data quality flags
    is_zero_spend       BOOLEAN         DEFAULT FALSE,
    is_zero_price       BOOLEAN         DEFAULT FALSE,
    is_outlier_uv       BOOLEAN         DEFAULT FALSE,  -- units/visit outlier
    is_outlier_vh       BOOLEAN         DEFAULT FALSE,  -- visits/hh outlier
    _stg_loaded_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT stg_txn_pk PRIMARY KEY (week_end_date, store_num, upc)
);


CREATE TABLE IF NOT EXISTS staging.stg_products (
    upc             BIGINT          NOT NULL,
    category        VARCHAR(100)    NOT NULL,
    description     VARCHAR(255)    NOT NULL,
    manufacturer    VARCHAR(100),
    sub_category    VARCHAR(100),
    product_size    VARCHAR(50),
    CONSTRAINT stg_prod_pk PRIMARY KEY (upc)
);


CREATE TABLE IF NOT EXISTS staging.stg_stores (
    store_num               INTEGER         NOT NULL,
    store_name              VARCHAR(100),
    city                    VARCHAR(100),
    state                   VARCHAR(10)     NOT NULL,
    msa_code                INTEGER,
    seg_value_name          VARCHAR(50)     NOT NULL,
    parking_space_qty       NUMERIC(8, 2),
    sales_area_size_num     INTEGER,
    avg_weekly_baskets      NUMERIC(12, 2),
    CONSTRAINT stg_store_pk PRIMARY KEY (store_num)
);


-- ============================================================
-- 3. DIMENSION TABLES — Star Schema
-- ============================================================

-- 3a. dim_calendar
CREATE TABLE IF NOT EXISTS marts.dim_calendar (
    date_key            INTEGER         NOT NULL,   -- YYYYMMDD surrogate key
    week_end_date       DATE            NOT NULL,
    year                INTEGER         NOT NULL,
    quarter             INTEGER         NOT NULL,
    month               INTEGER         NOT NULL,
    month_name          VARCHAR(20)     NOT NULL,
    week_num            INTEGER         NOT NULL,   -- ISO week number
    week_of_year        INTEGER         NOT NULL,   -- sequential 1–156
    is_holiday_season   BOOLEAN         DEFAULT FALSE,
    CONSTRAINT dim_cal_pk PRIMARY KEY (date_key)
);

COMMENT ON TABLE marts.dim_calendar IS
    '156-week date spine from first to last week in dataset.';


-- 3b. dim_product
CREATE TABLE IF NOT EXISTS marts.dim_product (
    upc                 BIGINT          NOT NULL,
    description         VARCHAR(255)    NOT NULL,
    category            VARCHAR(100)    NOT NULL,
    sub_category        VARCHAR(100),
    manufacturer        VARCHAR(100),
    product_size        VARCHAR(50),
    -- Derived attributes
    category_code       VARCHAR(10),
    CONSTRAINT dim_prod_pk PRIMARY KEY (upc)
);

COMMENT ON TABLE marts.dim_product IS
    '58 unique products spanning Mouthwash, Pretzels, Frozen Pizza, and Boxed Cereal.';


-- 3c. dim_store
CREATE TABLE IF NOT EXISTS marts.dim_store (
    store_num               INTEGER         NOT NULL,
    store_name              VARCHAR(100),
    city                    VARCHAR(100),
    state                   VARCHAR(10),
    msa_code                INTEGER,
    seg_value_name          VARCHAR(50),
    parking_space_qty       NUMERIC(8, 2),
    sales_area_size_num     INTEGER,
    avg_weekly_baskets      NUMERIC(12, 2),
    -- Derived segments
    store_size_band         VARCHAR(20),    -- Small / Medium / Large
    parking_band            VARCHAR(20),    -- Low / Medium / High
    CONSTRAINT dim_store_pk PRIMARY KEY (store_num)
);

COMMENT ON TABLE marts.dim_store IS
    '79 retail stores: Upscale, Mainstream, Value segments across 18+ US states.';


-- 3d. fact_sales
CREATE TABLE IF NOT EXISTS marts.fact_sales (
    fact_id             BIGSERIAL       NOT NULL,
    -- Foreign keys
    date_key            INTEGER         NOT NULL    REFERENCES marts.dim_calendar(date_key),
    store_num           INTEGER         NOT NULL    REFERENCES marts.dim_store(store_num),
    upc                 BIGINT          NOT NULL    REFERENCES marts.dim_product(upc),
    -- Measures
    units               INTEGER         NOT NULL    DEFAULT 0,
    visits              INTEGER         NOT NULL    DEFAULT 0,
    hhs                 INTEGER         NOT NULL    DEFAULT 0,
    spend               NUMERIC(12, 4)  NOT NULL    DEFAULT 0,
    price               NUMERIC(10, 4)  NOT NULL,
    base_price          NUMERIC(10, 4)  NOT NULL,
    -- Promotion flags
    feature             SMALLINT        NOT NULL    DEFAULT 0,
    display             SMALLINT        NOT NULL    DEFAULT 0,
    tpr_only            SMALLINT        NOT NULL    DEFAULT 0,
    -- Derived measures (pre-computed for performance)
    discount_pct        NUMERIC(8, 4),              -- (base_price - price) / base_price * 100
    price_gap           NUMERIC(10, 4),             -- base_price - price
    revenue_per_visit   NUMERIC(12, 4),             -- spend / NULLIF(visits, 0)
    units_per_hh        NUMERIC(10, 4),             -- units / NULLIF(hhs, 0)
    spend_per_hh        NUMERIC(12, 4),             -- spend / NULLIF(hhs, 0)
    promo_type          VARCHAR(30),                -- NONE/FEATURE/DISPLAY/TPR/COMBINED
    -- Quality flags
    is_promoted         BOOLEAN         DEFAULT FALSE,
    CONSTRAINT fact_sales_pk PRIMARY KEY (fact_id)
);

COMMENT ON TABLE marts.fact_sales IS
    'Central fact table: 524,945 rows (5 rows removed during cleaning). Grain: week × store × UPC.';


-- ============================================================
-- 4. AGGREGATE MART TABLES
-- ============================================================

-- Weekly store-category aggregate (pre-computed for performance)
CREATE TABLE IF NOT EXISTS marts.agg_weekly_store_category (
    date_key            INTEGER         NOT NULL,
    store_num           INTEGER         NOT NULL,
    category            VARCHAR(100)    NOT NULL,
    total_units         INTEGER,
    total_visits        INTEGER,
    total_hhs           INTEGER,
    total_spend         NUMERIC(14, 4),
    avg_price           NUMERIC(10, 4),
    avg_discount_pct    NUMERIC(8, 4),
    promo_weeks         INTEGER,
    CONSTRAINT agg_wsc_pk PRIMARY KEY (date_key, store_num, category)
);

-- Product performance summary (refreshed weekly)
CREATE TABLE IF NOT EXISTS marts.agg_product_summary (
    upc                 BIGINT          NOT NULL,
    description         VARCHAR(255),
    category            VARCHAR(100),
    total_revenue       NUMERIC(14, 4),
    total_units         BIGINT,
    total_visits        BIGINT,
    avg_price           NUMERIC(10, 4),
    avg_discount_pct    NUMERIC(8, 4),
    promo_weeks_pct     NUMERIC(8, 4),
    revenue_rank        INTEGER,
    abc_class           CHAR(1),
    CONSTRAINT agg_prod_pk PRIMARY KEY (upc)
);

-- Store performance summary
CREATE TABLE IF NOT EXISTS marts.agg_store_summary (
    store_num           INTEGER         NOT NULL,
    store_name          VARCHAR(100),
    seg_value_name      VARCHAR(50),
    state               VARCHAR(10),
    total_revenue       NUMERIC(14, 4),
    total_units         BIGINT,
    total_visits        BIGINT,
    avg_basket_value    NUMERIC(10, 4),
    revenue_per_sqft    NUMERIC(10, 4),
    revenue_rank        INTEGER,
    CONSTRAINT agg_store_pk PRIMARY KEY (store_num)
);


-- ============================================================
-- 5. INDEX RECOMMENDATIONS
-- ============================================================

-- fact_sales — most common filter patterns
CREATE INDEX IF NOT EXISTS idx_fact_date       ON marts.fact_sales (date_key);
CREATE INDEX IF NOT EXISTS idx_fact_store      ON marts.fact_sales (store_num);
CREATE INDEX IF NOT EXISTS idx_fact_upc        ON marts.fact_sales (upc);
CREATE INDEX IF NOT EXISTS idx_fact_promo      ON marts.fact_sales (is_promoted);
CREATE INDEX IF NOT EXISTS idx_fact_store_upc  ON marts.fact_sales (store_num, upc);
CREATE INDEX IF NOT EXISTS idx_fact_date_store ON marts.fact_sales (date_key, store_num);

-- dim_product — category filtering
CREATE INDEX IF NOT EXISTS idx_prod_category   ON marts.dim_product (category);
CREATE INDEX IF NOT EXISTS idx_prod_mfr        ON marts.dim_product (manufacturer);

-- dim_store — segment filtering
CREATE INDEX IF NOT EXISTS idx_store_seg       ON marts.dim_store (seg_value_name);
CREATE INDEX IF NOT EXISTS idx_store_state     ON marts.dim_store (state);

-- dim_calendar — date lookups
CREATE INDEX IF NOT EXISTS idx_cal_year        ON marts.dim_calendar (year);
CREATE INDEX IF NOT EXISTS idx_cal_quarter     ON marts.dim_calendar (year, quarter);

-- ============================================================
-- Performance Notes:
--   For Snowflake: Use CLUSTER BY (store_num, upc) on fact_sales
--   For BigQuery:  Partition fact_sales on week_end_date, cluster on upc, store_num
--   For PostgreSQL: Add BRIN index on date_key for time-range scans
-- ============================================================
