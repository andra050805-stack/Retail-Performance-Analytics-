# Data Dictionary
## SQL Retail Analytics — Dunnhumby "Breakfast at the Frat"

---

## Source Tables

### `raw.dh_transaction_data`

| Column | Type | Description | Business Meaning |
|---|---|---|---|
| `week_end_date` | DATE | Week ending date (Saturday) | Time dimension; dataset spans 156 weeks (2009–2012 approx.) |
| `store_num` | INTEGER | Unique store identifier | Foreign key to `dh_store_lookup` |
| `upc` | BIGINT | Universal Product Code | Foreign key to `dh_product_lookup` |
| `units` | INTEGER | Units sold in that week | Volume metric; occasionally 0 (out-of-stock or error) |
| `visits` | INTEGER | Unique purchase baskets containing this product | Frequency metric; distinct from households |
| `hhs` | INTEGER | Number of purchasing households | Reach metric; denominator for HH-level metrics |
| `spend` | NUMERIC | Total dollar revenue (units × shelf price) | Primary revenue metric; may be 0 for ~24 data quality rows |
| `price` | NUMERIC | Actual shelf price charged | What the consumer paid; may differ from base_price during promotions |
| `base_price` | NUMERIC | Regular (non-promotional) reference price | Represents the "normal" price; used to compute discount |
| `feature` | SMALLINT (0/1) | In-store circular feature flag | 1 = product advertised in weekly flyer |
| `display` | SMALLINT (0/1) | In-store display flag | 1 = product on an end-cap or secondary display |
| `tpr_only` | SMALLINT (0/1) | Temporary price reduction (shelf tag only) | 1 = price reduced but no feature or display support |

**Data Quality Notes:**
- ~24 rows have `spend = 0` despite having `units > 0` — revenue imputed as `units × price`
- 1 row has `price = 0` — `base_price` used as substitute price
- 2 store IDs (4503, 17627) appear twice in `dh_store_lookup` with conflicting `seg_value_name` — resolved by taking `MAINSTREAM` as primary segment
- `units/visit` outliers >10 flagged; `visits/hh` outliers >5 flagged

---

### `raw.dh_product_lookup`

| Column | Type | Description | Business Meaning |
|---|---|---|---|
| `upc` | BIGINT | Universal Product Code (Primary Key) | Unique product identifier |
| `category` | VARCHAR | Product category | One of: BAG SNACKS, COLD CEREAL, FROZEN PIZZA, ORAL HYGIENE PRODUCTS |
| `description` | VARCHAR | Full product description | Includes brand, flavor, and size |
| `manufacturer` | VARCHAR | Manufacturer name | Enables competitive and manufacturer-level analysis |
| `sub_category` | VARCHAR | Sub-category within category | More granular classification (e.g., MOUTHWASH within ORAL HYGIENE) |
| `product_size` | VARCHAR | Package size/quantity | Used for price-per-unit normalization |

---

### `raw.dh_store_lookup`

| Column | Type | Description | Business Meaning |
|---|---|---|---|
| `store_num` | INTEGER | Unique store identifier (Primary Key) | Matches `store_num` in transaction data |
| `store_name` | VARCHAR | Store location name (city name) | Descriptive only |
| `address_city_name` | VARCHAR | City of store | Geographic analysis |
| `address_state_prov_code` | VARCHAR | US state abbreviation | State-level aggregation (TX, CA, etc.) |
| `msa_code` | INTEGER | Metropolitan Statistical Area code | Metro market grouping |
| `seg_value_name` | VARCHAR | Store price/value segment | **Key segmentation variable**: Value / Mainstream / Upscale |
| `parking_space_qty` | NUMERIC | Number of parking spaces | Proxy for store footprint and access |
| `sales_area_size_num` | INTEGER | Store sales floor area (sq ft) | Size segmentation; used for revenue-per-sqft metric |
| `avg_weekly_baskets` | NUMERIC | Average weekly basket count | Store traffic volume baseline |

---

## Derived / Computed Fields

### Pricing Features (from Chapter 3.1 of ML notebook)

| Field | Formula | Interpretation |
|---|---|---|
| `discount_pct` | `(base_price - price) / base_price * 100` | % discount from regular price; avg ~5.7% across all rows |
| `price_gap` | `base_price - price` | Nominal dollar discount; avg ~$0.22 |
| `price_ratio` | `price / base_price` | 1.0 = no discount; <1 = discounted; outliers can exceed 1 |
| `log_price` | `LN(1 + price)` | Log-transformed price to reduce skewness; used in elasticity models |

### Sales Features (from Chapter 3.2 of ML notebook)

| Field | Formula | Interpretation |
|---|---|---|
| `revenue_per_visit` | `spend / NULLIF(visits, 0)` | Average $ per basket; avg ~$3.74 |
| `units_per_hh` | `units / NULLIF(hhs, 0)` | Purchase intensity per household; avg ~1.14 |
| `spend_per_hh` | `spend / NULLIF(hhs, 0)` | Revenue per household; avg ~$3.82 |
| `units_per_visit` | `units / NULLIF(visits, 0)` | Units per basket; avg ~1.12 |

### Promotion Classification

| `promo_type` Value | Condition | Description |
|---|---|---|
| `'NONE'` | feature=0, display=0, tpr_only=0 | No promotional support |
| `'FEATURE_ONLY'` | feature=1, display=0, tpr_only=0 | Circular only |
| `'DISPLAY_ONLY'` | feature=0, display=1, tpr_only=0 | In-store display only |
| `'TPR_ONLY'` | feature=0, display=0, tpr_only=1 | Shelf price reduction only |
| `'FEATURE_DISPLAY'` | feature=1, display=1, tpr_only=0 | Circular + display |
| `'FEATURE_TPR'` | feature=1, display=0, tpr_only=1 | Circular + price cut |
| `'DISPLAY_TPR'` | feature=0, display=1, tpr_only=1 | Display + price cut |
| `'COMBINED'` | feature=1, display=1, tpr_only=1 | Full promotion support |

### ABC Classification

| Class | Revenue Share | Description |
|---|---|---|
| `'A'` | Top 0–70% cumulative | High-value products; protect and invest |
| `'B'` | 70–90% cumulative | Mid-tier; optimize and monitor |
| `'C'` | 90–100% cumulative | Low-value; consider rationalization |

### Store Size Band

| Band | Sales Area (sq ft) | Description |
|---|---|---|
| `'Small'` | < 40,000 | Compact footprint |
| `'Medium'` | 40,000–60,000 | Standard supermarket |
| `'Large'` | > 60,000 | Supercenter/hypermarket scale |

---

## Metric Reference Card

| KPI | Formula | Unit |
|---|---|---|
| Total Revenue | `SUM(spend)` | USD |
| Avg Basket Value | `SUM(spend) / SUM(visits)` | USD / visit |
| Avg Basket Size | `SUM(units) / SUM(visits)` | Units / visit |
| Revenue per HH | `SUM(spend) / SUM(hhs)` | USD / household |
| Promotion Rate | `SUM(CASE WHEN is_promoted THEN 1 END) / COUNT(*)` | % of rows |
| Avg Discount | `AVG(discount_pct)` | % |
| Revenue per Sq Ft | `SUM(spend) / sales_area_size_num` | USD / sq ft |
| Price Elasticity Proxy | `% change units / % change price` | Dimensionless |
| Promo Lift | `(promo_units - baseline_units) / baseline_units * 100` | % |
| Market Share | `product_revenue / category_revenue * 100` | % |

---

*Last updated: SQL Retail Analytics v1.0 | Dunnhumby Breakfast at the Frat*
