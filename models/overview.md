{% docs __overview__ %}

# Florret Analytics - dbt Project

## Purpose

This dbt project transforms raw data from Florret's e-commerce and marketing platforms into analytics-ready models for business intelligence and reporting.

## Business Context

Florret is a flooring company with a unique business model:
- **Two Shopify stores**: Regular (DTC-focused, $55 product threshold) and Commercial (Trade-focused, $40 product threshold)
- **Sample-to-purchase funnel**: Core business metric tracking customers from sample orders to product purchases
- **Product categories**: Base, Signature, Craftsman, Silvan Hardwood, Iona
- **Line item classification**: Sample, Product, or Accessories based on complex SKU/title/price logic

## Data Sources

### E-commerce & Orders
- **Shopify (Regular)** - `ft_shopify_shopify`: Consumer-focused orders, $55 product threshold, default salesperson "DTC"
- **Shopify (Commercial)** - `ft_shopify_commercial_shopify`: Trade-focused orders, $40 product threshold, default salesperson "Commercial"

### Marketing & Attribution
- **Google Analytics 4** - `analytics_266190494`: Website behavior, e-commerce events, traffic sources
- **Klaviyo** - `ft_klaviyo_klaviyo`: Email marketing campaigns, customer engagement, flow performance
- **HubSpot** - `ft_hubspot_hubspot`: CRM, deals pipeline, contact lifecycle
- **Facebook Ads** - `ft_facebook_ads_facebook_ads`: Paid social campaigns and performance
- **Google Ads** - `google_ads`: Paid search campaigns and performance

### Operations & Support
- **Amazon Seller Central** - `ft_amazon_seller_central_amazon_selling_partner`: Marketplace sales
- **Freightview** - `ft_freightview`: Shipping and freight management
- **Gladly** - `ft_gladly`: Customer support interactions

### Custom Business Logic
- **Analysis** - `analysis`: Pre-computed Florret business logic tables (funnel analysis, line item classification)

## Project Structure

```
models/
├── staging/           # Raw source data, light transformations
│   ├── shopify/       # Both regular and commercial Shopify
│   ├── ga4/           # GA4 events (sharded tables)
│   ├── klaviyo/       # Email marketing
│   ├── hubspot/       # CRM
│   ├── facebook_ads/  # Paid social
│   ├── google_ads/    # Paid search
│   ├── amazon/        # Marketplace
│   ├── gladly/        # Support
│   ├── freightview/   # Logistics
│   └── analysis/      # Custom business logic
│
├── intermediate/      # Business logic transformations
│   └── (to be built in Phase 3)
│
└── marts/            # Analytics-ready dimensional models
    ├── core/         # fct_orders, fct_order_lines, dim_customers
    ├── marketing/    # CAC, ROAS, attribution, campaign performance
    └── operations/   # Shipping, fulfillment, inventory
```

## Naming Conventions

### Models
- **Staging**: `stg_{source}__{table}`
  - Example: `stg_shopify__orders`, `stg_ga4__events`
- **Intermediate**: `int_{entity}__{description}`
  - Example: `int_shopify__customer_order_history`, `int_shopify__line_items_classified`
- **Marts Fact Tables**: `fct_{entity}`
  - Example: `fct_orders`, `fct_order_lines`
- **Marts Dimension Tables**: `dim_{entity}`
  - Example: `dim_customers`, `dim_products`

### Columns
- **Boolean flags**: `is_{condition}` or `has_{condition}`
  - Example: `is_sample`, `has_coupon`
- **Dates**: `{entity}_{date/timestamp}`
  - Example: `order_date`, `processed_timestamp`
- **Counts**: `{entity}_count` or `total_{entities}`
  - Example: `order_count`, `total_samples`
- **Amounts**: `{metric}_amount` or `total_{metric}`
  - Example: `discount_amount`, `total_price`

## Key Business Rules

Critical Florret-specific logic implemented in this project:

### 1. Customer Identification
**Primary key: `email` (lowercased), NOT `customer_id`**
- Handles guest checkouts (no customer_id)
- Tracks across devices
- All lifetime metrics partition by `LOWER(email)`

### 2. Canonical Timestamp
**Use `processed_at` (not `created_at`) for time-series analysis**
- `processed_at` = when payment was captured
- Must convert to Pacific time: `DATETIME(processed_at, "America/Los_Angeles")`

### 3. Line Item Classification
Every line item is classified as Sample, Product, or Accessories:

**Sample** if ANY:
- Title contains 'Cut', 'Sample', or 'Plank'
- SKU contains 'CUT' or 'FULL'

**Product** if:
- Price > $55 (regular) OR price > $40 (commercial)
- Title does NOT contain 'Nosing'
- NOT a Sample

**Accessories**: Everything else

### 4. Order Type Classification
At order level (after line item aggregation):

- **Product Order**: `product_quantity > 0` AND `net_sales > $250`
- **Sample Order**: `sample_quantity > 0` AND `product_quantity = 0`
- **Accessory Only**: `accessories_quantity > 0` AND no samples/products

Note: $250 threshold prevents small product add-ons to sample orders from counting as product orders.

### 5. Product Categories
Derived from SKU patterns (see business_rules.md sections 3-4):
- Base (entry-level LVP)
- Signature (mid-tier LVP)
- Craftsman (premium LVP)
- Silvan Hardwood
- Iona
- Other

### 6. Sample-to-Purchase Conversion
Key dates calculated per customer (window functions over email):
- `first_sample_order_date`: First order with samples only
- `first_product_order_date`: First order with products
- `first_cut_order_date`: First order with cut samples
- `first_plank_order_date`: First order with plank samples

Conversion metrics:
- `days_to_order`: Days from first sample to first product order
- Conversion windows: 15d, 30d, 60d, 120d
- `conversion_ind`: Binary flag if customer ever converted

## Data Quality Notes

### Exclusions
Standard filters applied in analysis:
- `email NOT LIKE '%amazon%'` - Exclude marketplace orders
- `first_sample_order_date > '2020-12-31'` - Funnel analysis focuses on 2021+
- `email IS NOT NULL` - Required for customer-level metrics

### Field Preferences
- **Revenue**: Use `subtotal_price` (not `total_price`) for "sales" metrics
- **Customer ID**: Use `email` (lowercased), not `customer_id`
- **Order Date**: Use `processed_at`, not `created_at`
- **Customer Type/Group**: Extract from `tags` field using regex

## Semantic Metadata

All source files include rich semantic metadata for:
- **Measure vs Dimension identification**: Know which fields to aggregate vs group by
- **Aggregation defaults**: SUM, COUNT, AVG for measures
- **Business terms**: Synonyms for LLM query generation (e.g., "sales" = subtotal_price)
- **Time grains**: Available rollup levels (day, week, month, quarter, year)
- **Cardinality**: Low/medium/high for dimensions
- **Join keys**: Primary and foreign key relationships
- **Thresholds**: Business logic values ($55, $40, $250)

This metadata enables:
- LLM-powered query generation
- Accurate metric calculations
- Business context for development

## Development Workflow

### Phase 1: Sources (COMPLETE)
✅ Documented all 11 data sources with enriched metadata
✅ Platform knowledge + Florret business rules integrated

### Phase 2: Feasibility Analysis (NEXT)
- Analyze wishlist metrics against available data
- Classify as feasible/infeasible/ambiguous
- Generate client questions

### Phase 3: Model Development
- Build staging models (light transformations)
- Build intermediate models (business logic)
- Build mart models (analytics-ready)

## Getting Started

1. **Configure your profile**: Copy `profiles.yml.example` to `~/.dbt/profiles.yml` and configure BigQuery credentials
2. **Install dependencies**: `dbt deps` (if any packages specified)
3. **Test connection**: `dbt debug`
4. **Compile models**: `dbt compile` (builds manifest.json)
5. **Run staging**: `dbt run --select staging.*`

## Resources

- **Business Rules**: See `business_rules.md` in project root for complete Florret business logic
- **Source Documentation**: Each staging folder has `_*__sources.yml` with full field descriptions
- **dbt Docs**: Run `dbt docs generate` and `dbt docs serve` to view project documentation

---

*This project uses dbt to transform raw data into analytics-ready models following Florret's unique business logic and sample-to-purchase conversion tracking.*

{% enddocs %}
