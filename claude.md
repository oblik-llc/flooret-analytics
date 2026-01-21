# Flooret Analytics - dbt Project

## Project Overview

This is a dbt project for Flooret, a flooring company, transforming raw e-commerce and marketing data from BigQuery into analytics-ready models. The project emphasizes Flooret's unique sample-to-purchase business model and complex product classification logic.

**Platform:** dbt + BigQuery
**Status:** Phase 1 complete (enriched source documentation), models not yet built

## Critical Business Context

### Flooret's Unique Business Model

Flooret operates a sample-to-purchase funnel where customers:
1. Order samples (cut samples or full planks)
2. Evaluate products at home
3. Convert to product purchases

This funnel is the **core business metric** and drives most analytics requirements.

### Two Shopify Stores

The company operates two separate Shopify instances with different thresholds:

| Store | Source | Product Threshold | Default Salesperson |
|-------|--------|------------------|---------------------|
| Regular | `ft_shopify_shopify` | $55 | DTC |
| Commercial | `ft_shopify_commercial_shopify` | $40 | Commercial |

**Important:** Business logic is identical except for price thresholds. Consider whether to union early (with `store` dimension) or keep separate.

## Foundational Rules (CRITICAL)

### 1. Customer Identification
**Always use `email` (lowercased) as the primary customer identifier, NOT `customer_id`**

Reason:
- Handles guest checkouts (where `customer_id` is NULL)
- Tracks customers across devices
- All lifetime metrics must partition by `LOWER(email)`

### 2. Canonical Timestamp
**Always use `processed_at` for time-series analysis, NOT `created_at`**

- `processed_at` = when payment was captured (canonical order date)
- `created_at` = when order record was created (may differ)
- **Must convert to Pacific time:** `DATETIME(processed_at, "America/Los_Angeles")`

### 3. Revenue Metric
**Use `subtotal_price` for "sales" metrics, NOT `total_price`**

- `subtotal_price` = order subtotal before tax/shipping
- `total_price` = includes tax and shipping (customer-facing total)
- Business reports use `subtotal_price` as the standard "sales" metric

## Line Item Classification

Every line item must be classified as Sample, Product, or Accessories using this logic:

### Sample
A line item is a **Sample** if ANY of:
- `sku` starts with 'SA-' (primary, newer products)
- `sku` starts with 'KIT' (sample kits)
- `title` contains 'Cut', 'Sample', or 'Plank' (legacy fallback)
- `sku` contains 'CUT' or 'FULL' (legacy fallback)

### Product
A line item is a **Product** if:
- `sku` starts with 'FL-' (primary, newer products)
- OR (`price > 55` for regular store OR `price > 40` for commercial store)
- AND `title` does NOT contain 'Nosing'
- AND it doesn't qualify as a Sample

### Accessories/Other
A line item is **Accessories** if:
- `sku` starts with 'AC-' (primary, newer products)
- OR it doesn't qualify as Sample or Product

**Note:** Older products and data imports may not follow SKU prefix patterns. Use title/price as fallback.

### Sample Type Sub-Classification
Samples further classified as:
- **Sample - Cut**: `title` contains 'Cut' OR `sku` contains 'CUT' OR `title` contains 'Sample'
- **Sample - Plank**: `title` contains 'Plank' OR `sku` contains 'FULL'

## Order Classification

At the order level (after aggregating line items):

- **Product Order**: `product_quantity > 0` AND `net_sales > 250`
- **Sample Order**: `sample_quantity > 0` AND `product_quantity = 0`
- **Accessory Only**: `accessories_quantity > 0` AND `sample_quantity = 0` AND `product_quantity = 0`

**Note:** The $250 threshold prevents sample orders with small product add-ons from counting as product orders.

## Product Categories

Product categories are derived from SKU patterns in a two-step process:

### Step 1: Extract `category_shopify` from SKU
Uses regex patterns to extract B/C/S codes or last segment of SKU (see business_rules.md section 3 for details)

### Step 2: Map to Product Category

| category_shopify | Product Category |
|------------------|------------------|
| `lvp-S`, `lvp-7210` | Signature (mid-tier LVP) |
| `lvp-B`, `lvp-4805` | Base (entry-level LVP) |
| `lvp-C` | Craftsman (premium LVP) |
| `lvp-7`, `lvp-7T` | Silvan Hardwood |
| Everything else | Other |

**Additional product line:** Iona (mentioned in pivots but not in category mapping logic)

## Customer Segmentation

### Customer Group
Extracted from customer `tags`:
- **Retail**: Tags contain 'Retail' OR 'Guest' OR tags is empty
- **Trade Rewards**: Tags contain 'Trade' OR 'Legacy TR' OR 'Partner Plus' (AND NOT 'Pending')
- **Pending Trade Rewards**: Tags contain 'Pending'

### Customer Type
Extracted from customer `tags` using: `regexp_extract(tags, r'Customer Type: (.*?),')`
Default: 'DTC' (Direct to Consumer)

### Salesperson
Extracted from order `tags` using: `regexp_extract(tags, r'Salesperson: (.*?),')`
Default: 'DTC' for regular orders, 'Commercial' for commercial orders

## Sample-to-Purchase Conversion Tracking

### Key Date Fields (Per Customer)
Calculate using window functions partitioned by `email`:

- `first_sample_order_date`: MIN(`processed_at`) WHERE `sample_quantity > 0` AND `product_quantity = 0`
- `first_product_order_date`: MIN(`processed_at`) WHERE `product_quantity > 0`
- `first_cut_order_date`: MIN(`processed_at`) WHERE sample type = 'Sample - Cut'
- `first_plank_order_date`: MIN(`processed_at`) WHERE sample type = 'Sample - Plank'

### Conversion Metrics
- `days_to_order`: `DATE_DIFF(first_product_order_date, first_sample_order_date, DAY)`
- `conversion_ind`: 1 if customer ever placed a product order
- **Conversion windows**: 15 days, 30 days, 60 days, 120 days

### Customer Status Per Order
- **New Customer**: `order_date = first_product_order_date`
- **New Customer Sample**: `order_date = first_sample_order_date`
- **Returning Sample**: `order_date > first_sample_order_date` AND sample order
- **Returning Customer**: `order_date > first_product_order_date` AND product order

## Data Sources

### E-commerce (Primary)
- **Shopify Regular**: `ft_shopify_shopify` - Consumer orders, $55 threshold
- **Shopify Commercial**: `ft_shopify_commercial_shopify` - Trade orders, $40 threshold

### Marketing & Attribution
- **Google Analytics 4**: `analytics_266190494` - Website events, e-commerce tracking
- **Klaviyo**: `ft_klaviyo_klaviyo` - Email campaigns, flows
- **HubSpot**: `ft_hubspot_hubspot` - CRM, deals pipeline
- **Facebook Ads**: `ft_facebook_ads_facebook_ads` - Paid social
- **Google Ads**: `google_ads` - Paid search

### Operations
- **Amazon**: `ft_amazon_seller_central_amazon_selling_partner` - Marketplace sales
- **Freightview**: `ft_freightview` - Shipping/logistics
- **Gladly**: `ft_gladly` - Customer support

### Custom Business Logic
- **Analysis**: `analysis` - Pre-computed Flooret business metrics

## Project Structure

```
models/
├── staging/           # Raw source data, light transformations only
│   ├── shopify/       # Both stores documented here
│   ├── ga4/           # GA4 events (sharded tables)
│   ├── klaviyo/       # Email marketing
│   ├── hubspot/       # CRM
│   └── ...            # Other sources
│
├── intermediate/      # Business logic transformations (NOT YET BUILT)
│   └── (to be built in Phase 3)
│
└── marts/            # Analytics-ready dimensional models (NOT YET BUILT)
    ├── core/         # fct_orders, fct_order_lines, dim_customers
    ├── marketing/    # CAC, ROAS, attribution
    └── operations/   # Shipping, fulfillment
```

## dbt Conventions

### Model Naming
- **Staging**: `stg_{source}__{table}` (e.g., `stg_shopify__orders`)
- **Intermediate**: `int_{entity}__{description}` (e.g., `int_shopify__line_items_classified`)
- **Marts Fact**: `fct_{entity}` (e.g., `fct_orders`)
- **Marts Dimension**: `dim_{entity}` (e.g., `dim_customers`)

### Column Naming
- **Booleans**: `is_{condition}` or `has_{condition}`
- **Dates**: `{entity}_{date/timestamp}`
- **Counts**: `{entity}_count` or `total_{entities}`
- **Amounts**: `{metric}_amount` or `total_{metric}`

### Materialization
- **Staging models**: View (defined in dbt_project.yml)
- **Intermediate models**: View (defined in dbt_project.yml)
- **Mart models**: Table (defined in dbt_project.yml)

## Data Exclusions & Filters

Standard filters applied in analysis:
- `email NOT LIKE '%amazon%'` - Exclude Amazon marketplace orders from customer metrics
- `first_sample_order_date > '2020-12-31'` - Funnel analysis focuses on 2021+
- `email IS NOT NULL` - Required for customer-level analysis
- `customer_id IS NOT NULL` - Exclude orders without customer linkage (where needed)

## Source Documentation Features

All source YAML files (`models/staging/*/`) include enriched metadata:

- **Platform-specific descriptions**: Leveraging knowledge of Shopify, GA4, Klaviyo APIs
- **Flooret business rules**: References to business_rules.md sections
- **Semantic metadata**:
  - `semantic_type`: measure vs dimension
  - `default_aggregation`: SUM, COUNT, AVG
  - `business_terms`: Synonyms for query generation
  - `time_grains`: Available rollup levels
  - `thresholds`: Business logic values ($55, $40, $250)
  - `use_instead`: Field preference warnings

This metadata enables LLM-powered query generation and accurate metric calculations.

## Common Development Tasks

### Setting Up
```bash
# Install dbt
pip install dbt-bigquery

# Configure profiles
cp profiles.yml.example ~/.dbt/profiles.yml
# Edit ~/.dbt/profiles.yml with your BigQuery credentials

# Test connection
dbt debug

# Compile project and build manifest
dbt compile
```

### Building Models
```bash
# Run all models
dbt run

# Run specific layer
dbt run --select staging.*
dbt run --select intermediate.*
dbt run --select marts.*

# Run specific model and downstream dependencies
dbt run --select stg_shopify__orders+
```

### Documentation
```bash
# Generate and serve documentation
dbt docs generate
dbt docs serve
```

## Important Notes

### When Building Models

1. **Always classify line items first** - This is foundational for all downstream metrics
2. **Aggregate to order level carefully** - Sum quantities by classification type
3. **Use email for customer metrics** - Never use customer_id for lifetime calculations
4. **Convert timestamps to Pacific** - Required for date-based analysis
5. **Apply the $250 threshold** - Product orders must have `net_sales > 250`
6. **Handle both Shopify stores** - Consider unioning early with a `store` dimension

### Field Preferences (Critical)

When you see these fields, use the preferred alternative:

| Avoid | Use Instead | Reason |
|-------|-------------|--------|
| `customer_id` | `email` (lowercased) | Handles guest checkouts |
| `created_at` | `processed_at` | Canonical order timestamp |
| `total_price` | `subtotal_price` | Standard for "sales" metrics |
| `user_id` | `email` | Primary customer identifier |

### SKU Pattern Matching

For newer products, SKU prefixes are primary indicators:
- **SA-** or **KIT** = Sample
- **FL-** = Product
- **AC-** = Accessory

For legacy products, fall back to title/price-based rules.

### Color Extraction

Product color extracted from title: `REGEXP_EXTRACT(title, r'^(.+?)\s')`
Takes the first word before a space.

## Reference Documents

- **business_rules.md** - Complete Flooret business logic (20 detailed sections)
- **SEMANTIC_ENRICHMENT_PROCESS.md** - How source metadata was generated
- **models/overview.md** - Project overview (displayed in dbt docs)
- **models/staging/*/_*__sources.yml** - Enriched source documentation

## Development Philosophy

- **Phase 1 (Complete)**: Enriched source documentation with semantic metadata
- **Phase 2 (Next)**: Feasibility analysis of wishlist metrics
- **Phase 3 (Future)**: Build staging → intermediate → marts models

When building models:
- Start with staging (light transformations only)
- Move business logic to intermediate layer
- Keep marts focused on analytics-ready output
- Reference business_rules.md sections in model documentation
- Add tests for critical thresholds and classifications

## Questions or Clarifications

For Flooret-specific business logic, always check `business_rules.md` first. It contains 20 detailed sections covering:
- Line item classification (sections 1-2)
- Product categories (section 3)
- Customer segmentation (sections 4-6)
- Order classification (section 7)
- Conversion tracking (sections 8-9, 12-14)
- Pricing and revenue (sections 15, 17)
- Data handling (sections 18-20)
