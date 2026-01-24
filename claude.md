# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Type

This is a **dbt (data build tool) analytics project** for Flooret, a flooring e-commerce company. It transforms raw data from BigQuery into analytics-ready models for business intelligence.

## Essential Commands

### dbt Core Commands
```bash
# Parse project structure without BigQuery connection (validates Jinja/YAML)
dbt parse

# Test BigQuery connection
dbt debug

# Compile SQL without running (validates syntax, generates manifest.json)
dbt compile

# Run all models
dbt run

# Run specific models
dbt run --select staging.*
dbt run --select marts.core.*

# Run tests
dbt test

# Generate and serve documentation
dbt docs generate
dbt docs serve

# Clean target directory
dbt clean
```

### Project Setup
```bash
# Install dbt with BigQuery adapter
pip install dbt-bigquery

# Configure connection (copy example and edit)
cp profiles.yml.example ~/.dbt/profiles.yml
# Edit ~/.dbt/profiles.yml with your BigQuery credentials
```

## Critical Flooret Business Rules

These rules are implemented throughout the project. **Always reference `business_rules.md` for complete details.**

### Customer Identification
**USE `email` (lowercased), NOT `customer_id`**
- Handles guest checkouts (no customer_id assigned)
- Tracks customers across devices
- All lifetime metrics use `LOWER(email)` as partition key

### Canonical Timestamp
**USE `processed_at`, NOT `created_at`**
- `processed_at` = when payment was captured (canonical order date)
- Must convert to Pacific time: `DATETIME(processed_at, "America/Los_Angeles")`
- All time-series analysis uses Pacific timezone

### Line Item Classification
Every line item must be classified as Sample, Product, or Accessories:

**Sample** if ANY of:
- SKU starts with 'SA-' or 'KIT' (primary indicators)
- Title contains 'Cut', 'Sample', or 'Plank'
- SKU contains 'CUT' or 'FULL'

**Product** if:
- SKU starts with 'FL-' (primary indicator)
- OR (price > $55 for regular Shopify OR price > $40 for commercial Shopify)
- AND title does NOT contain 'Nosing'
- AND NOT a Sample

**Accessories**: Everything else or SKU starts with 'AC-'

### Order Classification
At order level (after line item aggregation):
- **Product Order**: `product_quantity > 0` AND `net_sales > $250`
  - $250 threshold prevents sample orders with small add-ons from counting as product orders
- **Sample Order**: `sample_quantity > 0` AND `product_quantity = 0`
- **Accessory Only**: `accessories_quantity > 0` AND no samples/products

### Two Shopify Stores
Flooret operates two separate Shopify instances with different thresholds:

| Store | Dataset | Price Threshold | Default Salesperson |
|-------|---------|----------------|---------------------|
| Regular (Consumer) | `ft_shopify_shopify` | $55 | DTC |
| Commercial (Trade) | `ft_shopify_commercial_shopify` | $40 | Commercial |

### Revenue Metrics
**USE `subtotal_price`, NOT `total_price`**
- `subtotal_price` = order subtotal before tax (used for "sales" metrics)
- `total_price` = includes tax and shipping (used for order classification)

### Product Categories
Derived from SKU patterns (see business_rules.md section 3):
- Base (entry-level LVP)
- Signature (mid-tier LVP)
- Craftsman (premium LVP)
- Silvan Hardwood
- Iona
- Other

### Sample-to-Purchase Conversion
Core business metric tracking customers from sample orders to product purchases:
- `first_sample_order_date`: First order with samples only
- `first_product_order_date`: First order with products
- `days_to_order`: Days from first sample to first product order
- Conversion windows: 15d, 30d, 60d, 120d

## Architecture

### Layered Structure
```
staging/        → Raw source data, light transformations (VIEWs)
intermediate/   → Business logic transformations (VIEWs)
marts/          → Analytics-ready dimensional models (TABLEs)
  ├── core/     → fct_orders, fct_order_lines, dim_customers
  ├── marketing/→ CAC, ROAS, attribution
  └── operations/→ Shipping, fulfillment
```

### Data Sources
11 source datasets documented in `models/staging/*/`:
- **Shopify** (2 stores): Orders, line items, customers
- **GA4**: Website events, e-commerce tracking
- **Klaviyo**: Email campaigns, customer engagement
- **HubSpot**: CRM, deals pipeline
- **Facebook Ads**: Paid social performance
- **Google Ads**: Paid search performance
- **Amazon**: Marketplace sales
- **Freightview**: Shipping logistics
- **Gladly**: Customer support
- **Analysis**: Pre-computed business logic

### Naming Conventions
- Staging: `stg_{source}__{table}`
- Intermediate: `int_{entity}__{description}`
- Marts Facts: `fct_{entity}`
- Marts Dimensions: `dim_{entity}`
- Booleans: `is_{condition}` or `has_{condition}`

### Semantic Metadata
All source YAML files contain enriched metadata:
- `semantic_type`: measure vs dimension
- `default_aggregation`: SUM, COUNT, AVG
- `business_terms`: Synonyms for LLM query generation
- `time_grains`: Available rollup levels
- `thresholds`: Business logic values ($55, $40, $250)
- Platform-specific context (Shopify, GA4, Klaviyo patterns)

## Key Files

### Core Project Documentation
- `dbt_project.yml`: Project configuration, materialization defaults
- `business_rules.md`: **Complete Flooret business logic** extracted from analyst's queries. Defines line item classification, customer identification (email vs household), order types, conversion metrics, pricing thresholds, and all business calculations. Reference this frequently when implementing models.
- `wishlist.md`: **Business metrics wishlist** organized by business function (Executive, Marketing, Customer Intelligence, Operations, etc.). Describes desired metrics, analysis goals, and reporting requirements. Used to prioritize analytics development.

### Implementation Documentation
- `ASSUMPTIONS_AND_LIMITATIONS.md`: **YELLOW/RED metrics documentation** with client action items for blocked metrics (COGS, Gladly schema, inventory data, etc.)
- `HOUSEHOLD_CONVERSION_TRACKING.md`: **Enhanced conversion tracking** implementation guide with address-based household identification (NEW - Phase 2 enhancement)
- `SPRINT_1_SUMMARY.md` through `SPRINT_4_SUMMARY.md`: Sprint deliverables and validation queries
- `PHASE_3_VALIDATION.md`: **Phase 3 validation results** - Pre-BigQuery validation status, deprecation warnings, and next steps (NEW)
- `SEMANTIC_ENRICHMENT_PROCESS.md`: How source metadata was generated

### Model Documentation
- `models/overview.md`: Project overview (rendered in dbt docs)
- `models/staging/*/_.yml`: Enriched source definitions with semantic metadata
- `models/intermediate/schema.yml`: Intermediate model tests
- `models/marts/*/schema.yml`: Mart model tests (core, marketing, operations)
- `analysis/reconciliation_queries.sql`: Validation queries for existing tables

### Configuration
- `profiles.yml.example`: BigQuery connection template

## Development Guidelines

### When Creating Models
1. Always read relevant source YAML first to understand available fields
2. Reference `business_rules.md` for classification logic
3. Use `email` (lowercased) for customer identification
4. Use `processed_at` (Pacific timezone) for order dates
5. Apply correct price thresholds based on store (regular vs commercial)
6. Follow naming conventions (stg_, int_, fct_, dim_)

### When Writing SQL
- Convert timestamps to Pacific: `DATETIME(processed_at, "America/Los_Angeles")`
- Lowercase emails: `LOWER(email)`
- Use window functions for customer-level metrics (partitioned by email)
- Apply standard exclusions: `email NOT LIKE '%amazon%'`, `email IS NOT NULL`

### Materialization Defaults
Configured in `dbt_project.yml`:
- Staging: `view` (schema: staging)
- Intermediate: `view` (schema: intermediate)
  - **Exception:** `int_customer_funnel` is materialized as `table` for performance (complex aggregations)
- Marts: `table` (schema: marts)

## BigQuery Connection

Target project: `bigcommerce-313718`

Example profile configuration:
```yaml
flooret_analytics:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth  # or service_account with keyfile
      project: bigcommerce-313718
      dataset: analytics
      threads: 4
      timeout_seconds: 600
      location: US
```

## Common Patterns

### Customer Lifetime Metrics
```sql
-- Use email as partition key
SUM(product_quantity) OVER (PARTITION BY LOWER(email) ORDER BY processed_at) as lifetime_product_quantity
```

### Timezone Conversion
```sql
-- Always convert processed_at to Pacific
DATETIME(processed_at, "America/Los_Angeles") as order_datetime_pt
```

### Line Item Classification
```sql
CASE
  WHEN (LOWER(title) LIKE '%cut%' OR LOWER(title) LIKE '%sample%' OR LOWER(title) LIKE '%plank%'
        OR LOWER(sku) LIKE '%cut%' OR LOWER(sku) LIKE '%full%'
        OR sku LIKE 'SA-%' OR sku LIKE 'KIT%')
  THEN 'Sample'
  WHEN (price > 55 AND title NOT LIKE '%Nosing%' OR sku LIKE 'FL-%')
  THEN 'Product'
  ELSE 'Accessories'
END as line_item_type
```

## Project Status

Phase 1 (Setup): ✅ COMPLETE
- 11 data sources documented
- Enriched semantic metadata
- BigQuery connection configured

Phase 2 (Analytics Implementation): ✅ COMPLETE
- Sprint 1: Staging layer (10 models)
- Sprint 2: Core marts (7 models - orders, customers, sample funnel)
- Sprint 3: Marketing & operations (9 models)
- Sprint 4: Advanced analytics (5 models - funnel, cohorts, unit economics)
- 27 total SQL models with comprehensive test coverage
- Documentation: 4 sprint summaries + assumptions/limitations guide

**Metrics Status:**
- ✅ GREEN (60%): 35 metrics fully implemented
- 🟡 YELLOW (30%): 18 metrics with documented assumptions
- 🔴 RED (10%): 6 metrics blocked by missing data sources

**Key Documentation Files:**
- `SPRINT_1_SUMMARY.md` through `SPRINT_4_SUMMARY.md`: Sprint deliverables
- `ASSUMPTIONS_AND_LIMITATIONS.md`: YELLOW/RED metric documentation
- `analysis/reconciliation_queries.sql`: Validation queries

Phase 3 (Validation & Production): ✅ COMPLETE
- BigQuery Connection: ✅ OAuth configured via `gcloud auth application-default login`
- Model Execution: ✅ All 27 models run successfully
  - Staging: 10 views (analytics_staging)
  - Intermediate: 5 views + 1 table (analytics_intermediate)
  - Marts: 11 tables (analytics_marts)
- Key row counts:
  - fct_orders: 765K rows
  - fct_order_lines: 1.8M rows
  - dim_customers: 403K rows
  - fct_sample_conversions: 312K rows
- Bug fixes applied:
  - Removed empty `source_relation` filters from Shopify staging models
  - Materialized `int_customer_funnel` as table for performance
- Remaining:
  - Run `dbt test` for data quality validation
  - Execute reconciliation queries
  - Build Sigma dashboards
  - Address RED metrics (COGS, Gladly schema, attribution validation)

**Phase 3 Documentation:**
- `PHASE_3_VALIDATION.md`: Validation results and next steps
