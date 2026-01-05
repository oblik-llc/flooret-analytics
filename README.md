# Florret Analytics - dbt Project

Analytics transformation layer for Florret's e-commerce data built with dbt and BigQuery.

## Project Status

✅ **Phase 1 Complete**: Project structure created with enriched source documentation
- 11 data sources documented with semantic metadata
- Platform knowledge + Florret business rules integrated
- Production-ready source YAML files

## Quick Start

### 1. Install dbt

```bash
# Install dbt-bigquery
pip install dbt-bigquery

# Verify installation
dbt --version
```

### 2. Configure BigQuery Connection

Copy the example profiles and configure your credentials:

```bash
# Copy example to your dbt profiles directory
cp profiles.yml.example ~/.dbt/profiles.yml

# Edit with your credentials
# For development, you can use oauth (will open browser)
# For production, use service account with keyfile
```

Your `~/.dbt/profiles.yml` should look like:

```yaml
florret_analytics:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: bigcommerce-313718
      dataset: dbt_dev
      threads: 4
      timeout_seconds: 300
      location: US
```

### 3. Test Connection

```bash
cd florret_analytics
dbt debug
```

Expected output: "All checks passed!"

### 4. Compile Project & Build Manifest

```bash
# Compile all models (validates SQL and builds manifest.json)
dbt compile

# The manifest will be created at: target/manifest.json
```

This generates `target/manifest.json` which contains:
- All source metadata (11 enriched sources)
- Semantic layer information
- Model dependencies
- Column-level metadata for LLM query generation

### 5. View Documentation

```bash
# Generate and serve documentation
dbt docs generate
dbt docs serve
```

This opens a browser with:
- Interactive lineage graph
- Source and model documentation
- Column descriptions with business context
- Florret business rules

## Project Structure

```
florret_analytics/
├── dbt_project.yml              # Project configuration
├── profiles.yml.example         # BigQuery connection template
├── business_rules.md            # Florret business logic reference
├── SEMANTIC_ENRICHMENT_PROCESS.md  # How metadata was generated
│
├── models/
│   ├── overview.md              # Project overview (you are here in dbt docs)
│   │
│   ├── staging/                 # Source data with light transformations
│   │   ├── shopify/             # Shopify sources (regular + commercial)
│   │   ├── ga4/                 # Google Analytics 4 events
│   │   ├── klaviyo/             # Email marketing
│   │   ├── hubspot/             # CRM
│   │   ├── facebook_ads/        # Paid social
│   │   ├── google_ads/          # Paid search
│   │   ├── amazon/              # Marketplace
│   │   ├── gladly/              # Customer support
│   │   ├── freightview/         # Logistics
│   │   └── analysis/            # Custom Florret business logic
│   │
│   ├── intermediate/            # Business logic transformations
│   │   └── (Phase 3: to be built)
│   │
│   └── marts/                   # Analytics-ready models
│       ├── core/                # fct_orders, fct_order_lines, dim_customers
│       ├── marketing/           # CAC, ROAS, attribution
│       └── operations/          # Shipping, fulfillment
│
├── macros/                      # Reusable SQL functions
├── tests/                       # Data quality tests
└── seeds/                       # CSV reference data
```

## Data Sources

### E-commerce
- **Shopify (Regular)**: Consumer orders, $55 product threshold
- **Shopify (Commercial)**: Trade orders, $40 product threshold

### Marketing & Attribution
- **Google Analytics 4**: Website events, e-commerce tracking
- **Klaviyo**: Email campaigns and customer engagement
- **HubSpot**: CRM and sales pipeline
- **Facebook Ads**: Paid social performance
- **Google Ads**: Paid search performance

### Operations
- **Amazon Seller Central**: Marketplace sales
- **Freightview**: Shipping and logistics
- **Gladly**: Customer support

### Custom Logic
- **Analysis**: Pre-computed Florret business logic

## Key Features

### Enriched Source Documentation

All source YAML files include:

1. **Platform-specific descriptions** - Leveraging knowledge of Shopify, GA4, Klaviyo, etc.
2. **Florret business rules** - Line item classification, product categories, thresholds
3. **Semantic metadata** - Measure vs dimension, aggregations, time grains
4. **Field guidance** - Primary keys, canonical dates, join keys

Example from Shopify orders:

```yaml
- name: total_price_pres_amount
  description: "Order total in presentment currency. For Florret: Use subtotal_price
    for 'sales' metrics. For Product Order classification, must be >$250 (prevents
    sample orders with small add-ons from counting). See business_rules.md section 7."
  meta:
    semantic_type: measure
    default_aggregation: sum
    unit: USD
    thresholds:
      product_order_minimum: 250
```

### Critical Florret Business Logic

**Customer Identification**: Use `email` (lowercased), NOT `customer_id`
- Handles guest checkouts and cross-device tracking

**Canonical Timestamp**: Use `processed_at`, NOT `created_at`
- Must convert to Pacific time: `DATETIME(processed_at, "America/Los_Angeles")`

**Line Item Classification**: Sample, Product, or Accessories
- Complex SKU/title/price logic
- Different thresholds for regular ($55) vs commercial ($40) stores

**Sample-to-Purchase Funnel**: Core business metric
- Tracks customers from sample orders to product purchases
- Conversion windows: 15d, 30d, 60d, 120d

See `business_rules.md` for complete details.

## Development Phases

### Phase 1: Setup ✅ COMPLETE
- [x] Project structure created
- [x] BigQuery connection configured
- [x] Source documentation enriched
- [x] Manifest ready to build

### Phase 2: Feasibility Analysis (NEXT)
- [ ] Analyze wishlist metrics against sources
- [ ] Classify feasibility (feasible/infeasible/ambiguous)
- [ ] Generate client questions

### Phase 3: Model Development
- [ ] Staging models (stg_*)
- [ ] Intermediate models (int_*)
- [ ] Mart models (fct_*, dim_*)

## Manifest for LLM Query Generation

After running `dbt compile`, the manifest (`target/manifest.json`) contains:

- **All source metadata**: 11 enriched sources with 1,000+ columns
- **Semantic types**: Which fields are measures vs dimensions
- **Business terms**: Synonyms for LLM understanding ("sales" = subtotal_price)
- **Aggregations**: Default aggregation methods (SUM, COUNT, AVG)
- **Time grains**: Available rollup levels
- **Join keys**: Relationships between tables
- **Business logic**: Thresholds, formulas, warnings

This enables LLMs to:
- Generate accurate queries for visualizations
- Choose correct fields (email vs customer_id, processed_at vs created_at)
- Apply proper transformations (timezone, product classification)
- Understand Florret's unique business model

## Resources

- **Business Rules**: `business_rules.md` - Complete Florret business logic
- **Enrichment Process**: `SEMANTIC_ENRICHMENT_PROCESS.md` - How metadata was generated
- **dbt Docs**: https://docs.getdbt.com/
- **Project Overview**: Run `dbt docs serve` and view the Overview page

## Next Steps

1. **Install dbt**: `pip install dbt-bigquery`
2. **Configure profiles**: Copy `profiles.yml.example` to `~/.dbt/profiles.yml`
3. **Test connection**: `dbt debug`
4. **Build manifest**: `dbt compile`
5. **View docs**: `dbt docs generate && dbt docs serve`

Once the manifest is built, you can proceed to Phase 2 (feasibility analysis) or Phase 3 (model development).

---

**Questions?** See `business_rules.md` for detailed Florret business logic or `models/overview.md` for project navigation.
