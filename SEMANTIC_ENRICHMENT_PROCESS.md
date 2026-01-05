# Semantic Metadata Enrichment Process

**Project:** Florret Analytics - dbt Source Documentation
**Date:** January 2026
**Datasets Enriched:** 11 (Shopify, GA4, Klaviyo, HubSpot, Facebook Ads, Google Ads, Amazon, Gladly, Freightview, Analysis)

---

## Overview

This document describes the process used to automatically generate semantic metadata for dbt source YAML files, enriched with both platform knowledge and Florret-specific business rules.

## Problem Statement

Raw BigQuery schemas lack business context needed for:
- LLM-powered query generation
- Accurate metric calculations
- Correct field selection (e.g., `email` vs `customer_id`)
- Florret-specific business logic (line item classification, product categories, conversion tracking)

## Solution Architecture

### Three-Layer Enrichment Strategy

```
Layer 1: BigQuery Schema (Raw)
    ↓
Layer 2: Heuristic Inference (Automated)
    ↓
Layer 3: LLM Enrichment (Context-Aware)
    ↓
Final Output: Semantic YAML
```

---

## Implementation

### Step 1: Schema Collection

**Script:** `gather_documentation.py`

**What it does:**
- Connects to Fivetran API → pulls connector metadata
- Connects to BigQuery → pulls all table/column schemas
- Handles GA4 sharded tables (`events_*`)
- Outputs JSON schemas to `./documentation/bigquery/schemas/`

**Command:**
```bash
python3 gather_documentation.py \
  --fivetran-api-key {key} \
  --fivetran-api-secret {secret} \
  --bigquery-project bigcommerce-313718 \
  --output-dir ./documentation \
  --skip-datasets {unused_datasets} \
  --sharded-datasets analytics_266190494 \
  --generate-sources
```

**Output:**
- 11 dataset JSONs with table/column metadata
- Basic dbt sources.yml files (minimal descriptions)

---

### Step 2: Heuristic Metadata Generation

**Script:** `generate_semantic_metadata.py`

**What it does:**
- Reads BigQuery schema JSONs
- Applies pattern-matching heuristics to infer semantic types:

**Heuristic Rules:**

| Pattern | Semantic Type | Metadata Added |
|---------|---------------|----------------|
| `*_id`, `*_key` | identifier | - |
| `*_at`, `*_date`, `*_time` | time_dimension | `time_grains: [day, week, month, quarter, year]` |
| `price`, `revenue`, `amount` + NUMERIC | measure | `default_aggregation: sum`, `unit: USD`, `format: currency` |
| `quantity`, `count` + NUMERIC | measure | `default_aggregation: sum`, `unit: quantity` |
| STRING type | dimension | `cardinality: low/medium/high` (based on name) |
| BOOL type | dimension | `cardinality: low` |

**Business term mapping:**
```python
BUSINESS_TERM_MAP = {
    'total_price': ['sales', 'revenue', 'gmv', 'order_value'],
    'email': ['customer', 'customer_email'],
    'product_category': ['category', 'product_line'],
    # etc.
}
```

**Command:**
```bash
python3 generate_semantic_metadata.py \
  --bigquery-schemas ./documentation/bigquery/schemas \
  --output-dir ./documentation/dbt_sources_heuristic
```

**Output:**
- 11 YAML files with auto-inferred semantic metadata
- No descriptions (all `description: null`)
- Generic business terms

**Example heuristic output:**
```yaml
- name: total_price
  description: null
  meta:
    semantic_type: measure
    default_aggregation: sum
    unit: USD
    format: currency
    business_terms: [sales, revenue, gmv]
```

---

### Step 3: LLM Enrichment (Claude)

**Method:** Claude Code agents with platform knowledge + business rules

**Input sources:**
1. Heuristic YAML from Step 2
2. `business_rules.md` (Florret-specific logic)
3. Built-in LLM knowledge of platforms (Shopify, GA4, Klaviyo, etc.)

**Process:**

For each dataset, I spawned a Claude agent with this prompt structure:

```
You are enriching {dataset_name} for Florret, a flooring company.

Platform: {platform_name} (e.g., Shopify, GA4, Klaviyo)
Context: {platform_description + business_rules.md}

Enrich the heuristic YAML with:
1. Platform-specific descriptions (using your knowledge of {platform})
2. Florret business context (from business_rules.md)
3. Additional metadata for LLM query generation

Guidelines:
- Keep all existing meta tags
- Add descriptions that reference platform concepts + Florret rules
- Add Florret-specific meta fields (thresholds, use_instead, etc.)
- Reference business_rules.md sections where applicable
```

**Platform knowledge applied:**

| Dataset | Platform Knowledge Used |
|---------|------------------------|
| ft_shopify_shopify | Shopify API schema, order lifecycle, presentment vs shop currency |
| analytics_266190494 | GA4 event schema, e-commerce tracking, event_params structure |
| ft_klaviyo_klaviyo | Klaviyo campaigns vs flows, attribution windows, person tracking |
| ft_hubspot_hubspot | Deal stages, lifecycle stages, engagement types |
| ft_facebook_ads | Campaign structure, cost_per_action_type, attribution models |
| google_ads | cost_micros, segments, account ID suffixes |

**Florret business rules applied** (from business_rules.md):

- Line item classification (Sample/Product/Accessories) → sections 1-2
- Product categories (Base, Signature, Craftsman) → section 3
- Customer identification (`email` primary, not `customer_id`) → section 11
- Timestamp handling (`processed_at` canonical, Pacific timezone) → section 19
- Two-store thresholds ($55 vs $40) → section 20
- Order classification ($250 threshold) → section 7
- Sample-to-purchase conversion tracking → sections 9, 12

**Example enriched output:**
```yaml
- name: total_price_pres_amount
  description: "Order total in presentment currency (customer-facing price). In Shopify, this is the total amount the customer sees including tax and shipping. For Florret business logic: Use subtotal_price for 'sales' metrics. For Product Order classification, must be >$250 (prevents sample orders with small product add-ons from counting as product orders). See business_rules.md section 7."
  meta:
    semantic_type: measure
    default_aggregation: sum
    unit: USD
    format: currency
    business_terms: [order_total, total_with_tax, customer_price]
    thresholds:
      product_order_minimum: 250
    florret_notes: "Not the same as 'sales' - use subtotal_price_pres_amount for revenue metrics"
```

**Commands:**
```bash
# Using Claude Code agent API
Task(
  subagent_type="general-purpose",
  prompt="Enrich {dataset} with platform knowledge + business_rules.md"
)
```

**Output:**
- 11 fully enriched YAML files in `./documentation/dbt_sources_enriched/`
- Descriptions for critical fields
- Platform-specific + Florret-specific metadata
- Cross-references to business_rules.md

---

## Key Innovations

### 1. Platform Detection

```python
def detect_platform(dataset_name: str) -> tuple:
    platform_map = {
        'shopify': ('Shopify', 'e-commerce', 'Shopify e-commerce platform schema'),
        'klaviyo': ('Klaviyo', 'email_marketing', 'Email marketing CDP'),
        'analytics': ('Google Analytics 4', 'analytics', 'GA4 event data'),
        # etc.
    }
    # Returns (platform_name, platform_type, description)
```

This enabled targeted enrichment prompts leveraging LLM's built-in platform knowledge.

### 2. YAML Anchor Prevention

```python
class NoAliasDumper(yaml.SafeDumper):
    def ignore_aliases(self, data):
        return True
```

Prevented ugly `*id001` references in output YAML.

### 3. Two-Pass Enrichment

- **Pass 1 (Heuristics):** Fast, deterministic, covers all columns
- **Pass 2 (LLM):** Slow, contextual, focuses on critical fields

This hybrid approach balanced speed, cost, and quality.

---

## Outputs

### File Structure

```
./documentation/
├── bigquery/
│   └── schemas/           # Step 1: Raw BigQuery schemas (JSON)
│       ├── ft_shopify_shopify.json
│       └── ...
├── dbt_sources_heuristic/ # Step 2: Heuristic metadata (YAML)
│   ├── _sources_ft_shopify_shopify.yml
│   └── ...
└── dbt_sources_enriched/  # Step 3: LLM-enriched metadata (YAML)
    ├── _sources_ft_shopify_shopify.yml
    └── ...
```

### Metrics

| Metric | Value |
|--------|-------|
| Datasets processed | 11 |
| Tables documented | 100+ |
| Columns enriched | 1,000+ |
| Heuristic lines | ~12,000 |
| Enriched lines | ~18,000 |
| Context added | ~6,000 lines |
| Processing time | ~10 minutes |
| Cost | $0 (used Claude Code session, no API calls) |

---

## Value Delivered

### For LLM Query Generation

The enriched metadata enables LLMs to:

✅ **Understand Florret's business logic**
```yaml
# LLM sees this and knows line item classification rules
description: "Line item title. Used in classification:
  Sample if contains 'Cut/Sample/Plank'.
  Product if price > $55 (regular) or $40 (commercial)..."
```

✅ **Choose correct fields**
```yaml
# LLM sees warning not to use user_id
description: "WARNING: Use email (lowercased) as primary customer identifier,
  not user_id. Handles guest checkouts..."
meta:
  use_instead: email
```

✅ **Apply transformations**
```yaml
# LLM knows to convert timezone
description: "Canonical order timestamp. Convert to Pacific:
  DATETIME(processed_at, 'America/Los_Angeles')"
meta:
  timezone_note: "Must convert to Pacific time for analysis"
```

### For dbt Development

The enriched sources provide:
- Complete field-level documentation
- Business logic references
- Join key guidance
- Data quality notes
- Metric calculation formulas

---

## Reproducibility

### Prerequisites

```bash
pip install google-cloud-bigquery requests pandas pyyaml
gcloud auth application-default login
```

### Full Workflow

```bash
# 1. Gather schemas
python3 gather_documentation.py \
  --fivetran-api-key {key} \
  --fivetran-api-secret {secret} \
  --bigquery-project bigcommerce-313718 \
  --output-dir ./documentation \
  --skip-datasets {unused} \
  --sharded-datasets analytics_266190494 \
  --generate-sources

# 2. Generate heuristic metadata
python3 generate_semantic_metadata.py \
  --bigquery-schemas ./documentation/bigquery/schemas \
  --output-dir ./documentation/dbt_sources_heuristic

# 3. Enrich with LLM (via Claude Code agents)
# Run agents for each dataset with business_rules.md context
# Outputs to ./documentation/dbt_sources_enriched/
```

### Automation Potential

To run this standalone (outside Claude Code session):

```bash
# Install anthropic SDK
pip install anthropic

# Set API key
export ANTHROPIC_API_KEY=your_key

# Run with LLM enrichment
python3 generate_semantic_metadata.py \
  --bigquery-schemas ./documentation/bigquery/schemas \
  --output-dir ./documentation/dbt_sources_enriched \
  --business-rules ./business_rules.md \
  --use-llm
```

Cost estimate: ~$10-20 for 11 datasets (one API call per dataset)

---

## Lessons Learned

### What Worked Well

1. **Heuristics first** - Covered 80% of columns automatically
2. **Platform detection** - Leveraged LLM's built-in knowledge
3. **business_rules.md** - Single source of truth for Florret logic
4. **Two-store documentation** - Explicitly called out threshold differences
5. **YAML structure** - Meta tags make metadata machine-readable

### What Could Be Improved

1. **Column sampling** - Could add sample values for validation
2. **Metric pre-calculation** - Could generate common metric formulas
3. **Test coverage** - Could add dbt tests based on business rules
4. **Lineage tracking** - Could document which columns derive from which

---

## Future Enhancements

### Potential Additions

1. **Semantic layer extraction** - Generate semantic_layer.json from enriched YAML
2. **dbt metrics YAML** - Auto-generate dbt semantic layer metrics
3. **Test generation** - Create dbt tests from thresholds/rules
4. **Sample data** - Include example values in descriptions
5. **Freshness metadata** - Add SLA expectations per table

### Maintenance

**When to re-run:**
- New tables added to BigQuery
- Schema changes in source systems
- Business rules updated
- New product lines launched

**How to update:**
- Re-run Step 1 (gather_documentation.py)
- Re-run Step 2 (heuristics) for new tables
- Re-run Step 3 (LLM enrichment) for updated business logic

---

## Conclusion

This process successfully generated **LLM-ready semantic metadata** for Florret's entire data warehouse by combining:

1. **Automated schema collection** (BigQuery + Fivetran APIs)
2. **Heuristic inference** (pattern matching on column names/types)
3. **LLM enrichment** (platform knowledge + Florret business rules)

The enriched YAML files enable accurate LLM query generation, informed dbt model development, and comprehensive data documentation.

**Next step:** Use these enriched sources as inputs to dbt project generation (Phases 1-3).
