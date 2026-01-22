# Household Conversion Tracking - Enhanced Sample-to-Product Conversion Analysis

**Date:** 2026-01-21
**Feature:** Address-Based Household Identification for Conversion Tracking
**Status:** ✅ Implemented (Phase 2 Enhancement)

---

## Executive Summary

This feature enhances Flooret's sample-to-product conversion tracking by identifying conversions that occur at the **household level** rather than just the **email level**. It captures conversions where customers use different emails for sample orders vs. product orders but ship to the same physical address.

### Business Value

**Problem:**
Traditional email-based conversion tracking misses conversions when customers use different emails:
- Order sample on work email → send to home address
- Order product on personal/family email → send to same home address
- These appear as "no conversion" in email-only tracking, but they ARE conversions at the household level

**Solution:**
Household conversion tracking normalizes shipping addresses to create a household identifier, enabling accurate conversion measurement across all email addresses associated with a physical location.

### Key Metrics Available

| Metric Type | Email-Based (Original) | Household-Based (NEW) | Hybrid (NEW) |
|-------------|------------------------|----------------------|--------------|
| **Conversion Rate** | Same email sample → product | Same address sample → product | Email OR household conversion |
| **Days to Order** | Days from first email sample to first email product | Days from first household sample to first household product | Earliest of email or household |
| **Conversion Windows** | 15d, 30d, 60d, 120d (email) | 15d, 30d, 60d, 120d (household) | 15d, 30d, 60d, 120d (hybrid) |
| **Use Case** | Customer loyalty tracking | Household buying behavior | Complete conversion picture |

---

## Implementation Details

### Matching Logic (Client-Specified Requirements)

**Address Type:** Shipping address only
- Rationale: Most reliable for household identification (physical delivery location)
- Billing addresses vary with payment methods (credit cards, company accounts)

**Match Fields:** Shipping address line 1 + ZIP code
- Balance of precision and flexibility
- Handles minor variations in city/state formatting

**Address Normalization:** Standard best practices applied
1. **Lowercase:** Convert all text to lowercase (`Main St` → `main st`)
2. **Trim whitespace:** Remove leading/trailing spaces, collapse multiple spaces
3. **Remove punctuation:** Strip periods, commas, hyphens, hashtags (`123 Main St.` → `123 main st`)
4. **Standardize abbreviations:** Convert common street type abbreviations
   - Street → st, Avenue → ave, Drive → dr, Road → rd
   - Lane → ln, Court → ct, Circle → cir, Place → pl
   - Apartment → apt, Suite → ste, Building → bldg
   - North → n, South → s, East → e, West → w

**Household ID:** FARM_FINGERPRINT hash of normalized address + ZIP
- Deterministic integer ID (same address always gets same ID)
- Stable across multiple model runs
- No PII exposure in household_id field

---

## Data Models

### New Models Created

#### 1. `int_household_identification`
**Purpose:** Assigns household_id to each order based on normalized shipping address
**Grain:** order_id (one row per order)
**Key Fields:**
- `order_id` - Unique order identifier
- `email` - Customer email
- `household_id` - FARM_FINGERPRINT hash of normalized address + ZIP
- `household_key` - Human-readable concatenation (normalized address | ZIP)
- `normalized_address` - Normalized shipping address line 1
- `normalized_zip` - Normalized ZIP code (5 digits for US)
- `shipping_address_line1` - Raw address (for validation/debugging)
- `shipping_address_zip` - Raw ZIP (for validation/debugging)

**Exclusions:**
- Orders with null shipping address or ZIP
- Orders with null email
- Amazon marketplace orders (email LIKE '%amazon%')

**Example:**
```sql
-- Original addresses (3 different formats, same location)
'123 Main Street, Apt 4'  → normalized: '123 main st apt 4'
'123 Main St., #4'        → normalized: '123 main st apt 4'
'123 Main St Apartment 4' → normalized: '123 main st apt 4'

-- All get same household_id: FARM_FINGERPRINT('123 main st apt 4|94110')
```

#### 2. Enhanced `int_customer_funnel`
**Purpose:** Tracks conversions at BOTH email level AND household level
**Grain:** email (customer level) with household context
**Key Enhancements:**
- All original email-based metrics retained (backwards compatible)
- Added parallel household-based metrics
- Added `hybrid_conversion_ind` (email OR household)

**Email-Based Metrics (Original):**
- `first_sample_order_date` - First email sample order
- `first_product_order_date` - First email product order
- `days_to_order` - Days from email sample to email product
- `conversion_ind` - Did this email convert?
- `converted_within_15d/30d/60d/120d` - Email conversion windows

**Household-Based Metrics (NEW):**
- `household_id` - Household identifier
- `household_email_count` - Number of unique emails in household
- `household_first_sample_order_date` - First household sample order (any email)
- `household_first_product_order_date` - First household product order (any email)
- `household_days_to_order` - Days from household sample to household product
- `household_conversion_ind` - Did this household convert?
- `household_converted_within_15d/30d/60d/120d` - Household conversion windows

**Hybrid Metrics (NEW):**
- `hybrid_conversion_ind` - Converted at email level OR household level

#### 3. Enhanced `fct_sample_conversions`
**Purpose:** Dashboard-ready sample funnel table with household conversion metrics
**Grain:** email (customer level)
**Key Enhancements:**
- All household metrics from `int_customer_funnel` included
- Added `household_conversion_window_bucket` (time-based bucketing)
- Added `hybrid_conversion_window_bucket` (uses earliest conversion)

---

## Usage Examples

### Example 1: Measure Conversion Rate Lift from Household Tracking

**Question:** How much higher is the conversion rate when we include household conversions?

```sql
SELECT
  -- Email-only conversion rate (original metric)
  COUNT(DISTINCT CASE WHEN conversion_ind = 1 THEN email END) AS email_converters,
  COUNT(DISTINCT email) AS total_samplers,
  ROUND(COUNT(DISTINCT CASE WHEN conversion_ind = 1 THEN email END) * 100.0 / COUNT(DISTINCT email), 2) AS email_conversion_rate,

  -- Hybrid conversion rate (email OR household)
  COUNT(DISTINCT CASE WHEN hybrid_conversion_ind = 1 THEN email END) AS hybrid_converters,
  ROUND(COUNT(DISTINCT CASE WHEN hybrid_conversion_ind = 1 THEN email END) * 100.0 / COUNT(DISTINCT email), 2) AS hybrid_conversion_rate,

  -- Lift from household tracking
  ROUND(
    (COUNT(DISTINCT CASE WHEN hybrid_conversion_ind = 1 THEN email END) -
     COUNT(DISTINCT CASE WHEN conversion_ind = 1 THEN email END)) * 100.0 / COUNT(DISTINCT email),
    2
  ) AS conversion_rate_lift

FROM {{ ref('fct_sample_conversions') }}
WHERE first_sample_order_date >= '2024-01-01'
```

**Expected Output:**
| email_converters | total_samplers | email_conversion_rate | hybrid_converters | hybrid_conversion_rate | conversion_rate_lift |
|------------------|----------------|----------------------|-------------------|----------------------|----------------------|
| 1,200 | 5,000 | 24.00% | 1,350 | 27.00% | +3.00% |

**Interpretation:** Household tracking captures an additional 3% conversion rate that email-only tracking missed.

---

### Example 2: Identify Multi-Email Households

**Question:** Which households have multiple emails? What is their behavior?

```sql
SELECT
  household_id,
  household_email_count,
  -- Show all emails in household
  STRING_AGG(DISTINCT email, ', ' ORDER BY email) AS emails_in_household,

  -- Show conversion status
  MAX(conversion_ind) AS any_email_converted,
  MAX(household_conversion_ind) AS household_converted,

  -- Show order dates
  MIN(first_sample_order_date) AS first_sample_date,
  MIN(first_product_order_date) AS first_product_date,
  MIN(household_first_product_order_date) AS household_product_date

FROM {{ ref('fct_sample_conversions') }}
WHERE household_id IS NOT NULL
GROUP BY household_id, household_email_count
HAVING household_email_count > 1  -- only multi-email households
ORDER BY household_email_count DESC
LIMIT 100
```

**Use Case:** Identify households with complex buying patterns (multiple decision-makers, shared addresses, etc.)

---

### Example 3: Cohort Conversion Analysis (Email vs Household)

**Question:** How do email-based and household-based conversion rates compare by cohort month?

```sql
SELECT
  cohort_month,

  -- Email-based conversion metrics
  COUNT(DISTINCT email) AS cohort_size,
  COUNT(DISTINCT CASE WHEN conversion_ind = 1 THEN email END) AS email_converters,
  ROUND(COUNT(DISTINCT CASE WHEN conversion_ind = 1 THEN email END) * 100.0 / COUNT(DISTINCT email), 2) AS email_conversion_rate,

  -- Household-based conversion metrics
  COUNT(DISTINCT CASE WHEN household_conversion_ind = 1 THEN email END) AS household_converters,
  ROUND(COUNT(DISTINCT CASE WHEN household_conversion_ind = 1 THEN email END) * 100.0 / COUNT(DISTINCT email), 2) AS household_conversion_rate,

  -- Hybrid (email OR household)
  COUNT(DISTINCT CASE WHEN hybrid_conversion_ind = 1 THEN email END) AS hybrid_converters,
  ROUND(COUNT(DISTINCT CASE WHEN hybrid_conversion_ind = 1 THEN email END) * 100.0 / COUNT(DISTINCT email), 2) AS hybrid_conversion_rate

FROM {{ ref('fct_sample_conversions') }}
WHERE cohort_month >= '2024-01-01'
GROUP BY cohort_month
ORDER BY cohort_month
```

**Sigma Dashboard Recommendation:**
- Line chart with 3 lines: email_conversion_rate, household_conversion_rate, hybrid_conversion_rate
- Filter by cohort_month date range
- Annotations for marketing campaigns or product launches

---

### Example 4: Conversion Window Comparison

**Question:** Do households convert faster than individual emails?

```sql
SELECT
  -- Email-based conversion windows
  conversion_window_bucket AS email_window,
  COUNT(DISTINCT CASE WHEN conversion_ind = 1 THEN email END) AS email_converters,

  -- Household-based conversion windows
  household_conversion_window_bucket AS household_window,
  COUNT(DISTINCT CASE WHEN household_conversion_ind = 1 THEN email END) AS household_converters,

  -- Hybrid conversion windows
  hybrid_conversion_window_bucket AS hybrid_window,
  COUNT(DISTINCT CASE WHEN hybrid_conversion_ind = 1 THEN email END) AS hybrid_converters

FROM {{ ref('fct_sample_conversions') }}
WHERE first_sample_order_date >= '2024-01-01'
GROUP BY conversion_window_bucket, household_conversion_window_bucket, hybrid_conversion_window_bucket
ORDER BY
  CASE conversion_window_bucket
    WHEN '0-15 days' THEN 1
    WHEN '16-30 days' THEN 2
    WHEN '31-60 days' THEN 3
    WHEN '61-120 days' THEN 4
    WHEN '120+ days' THEN 5
    WHEN 'No Conversion' THEN 6
  END
```

---

### Example 5: Household Multi-Touch Attribution

**Question:** For households with multiple emails, which email ordered the sample and which ordered the product?

```sql
WITH household_details AS (
  SELECT
    household_id,
    household_email_count,
    STRING_AGG(DISTINCT email, ', ' ORDER BY email) AS emails_in_household,

    -- Find which email ordered sample first
    ARRAY_AGG(email ORDER BY first_sample_order_date LIMIT 1)[OFFSET(0)] AS sample_email,

    -- Find which email ordered product first (household-level)
    ARRAY_AGG(email ORDER BY household_first_product_order_date LIMIT 1)[OFFSET(0)] AS product_email,

    MIN(household_first_sample_order_date) AS household_sample_date,
    MIN(household_first_product_order_date) AS household_product_date,
    MIN(household_days_to_order) AS household_days_to_order

  FROM {{ ref('fct_sample_conversions') }}
  WHERE household_id IS NOT NULL
    AND household_conversion_ind = 1  -- only converted households
    AND household_email_count > 1     -- only multi-email households
  GROUP BY household_id, household_email_count
)

SELECT
  household_id,
  emails_in_household,
  sample_email,
  product_email,
  household_sample_date,
  household_product_date,
  household_days_to_order,

  -- Did same email place both orders?
  CASE WHEN sample_email = product_email THEN 'Same Email' ELSE 'Different Emails' END AS multi_email_conversion

FROM household_details
ORDER BY household_days_to_order
LIMIT 100
```

**Use Case:** Identify households where sample and product were ordered by different people (e.g., spouse orders sample, other spouse orders product)

---

## Sigma Dashboard Recommendations

### Dashboard 1: Conversion Rate Comparison
**Metrics:**
- Email-only conversion rate (%)
- Household conversion rate (%)
- Hybrid conversion rate (%)
- Conversion rate lift from household tracking (percentage points)

**Filters:**
- Date range (cohort_month)
- Sample order type
- Store (regular vs commercial)
- Region (first_sample_shipping_state)

**Visualizations:**
- KPI cards: Email vs Hybrid conversion rate side-by-side
- Line chart: Conversion rate trends over time (3 lines)
- Bar chart: Conversion rate by sample order type (grouped bars)

---

### Dashboard 2: Household Insights
**Metrics:**
- Total households
- Multi-email households (%)
- Average emails per household
- Household conversion rate

**Filters:**
- Date range
- Minimum household_email_count (e.g., show only 2+ email households)

**Visualizations:**
- KPI cards: Total households, multi-email %, avg emails/household
- Table: Top 100 multi-email households with details
- Scatter plot: household_email_count vs days_to_order

---

### Dashboard 3: Conversion Funnel Deep Dive
**Metrics:**
- Funnel stage counts: Sampled → Converted (email) → Converted (household) → Converted (hybrid)
- Dropoff rates at each stage

**Filters:**
- Cohort month
- Sample order type
- Conversion window bucket

**Visualizations:**
- Funnel chart: Sampled → Email converted → Household converted
- Stacked bar chart: Conversion window distribution (email vs household vs hybrid)

---

## Technical Validation Queries

### Validation 1: Check Address Normalization

```sql
-- Verify address normalization is working correctly
SELECT
  shipping_address_line1 AS raw_address,
  normalized_address,
  normalized_zip,
  COUNT(DISTINCT order_id) AS order_count

FROM {{ ref('int_household_identification') }}
GROUP BY raw_address, normalized_address, normalized_zip
ORDER BY order_count DESC
LIMIT 100
```

**Expected:** Similar addresses should normalize to same string

---

### Validation 2: Household ID Stability

```sql
-- Verify household_id is deterministic (same address = same ID)
SELECT
  household_key,
  household_id,
  COUNT(DISTINCT household_id) AS unique_household_ids,
  COUNT(DISTINCT email) AS unique_emails,
  COUNT(DISTINCT order_id) AS order_count

FROM {{ ref('int_household_identification') }}
GROUP BY household_key, household_id
HAVING COUNT(DISTINCT household_id) > 1  -- flag any instability
```

**Expected:** 0 rows (each household_key should have exactly 1 household_id)

---

### Validation 3: Conversion Logic Consistency

```sql
-- Verify hybrid_conversion_ind = email OR household
SELECT
  conversion_ind AS email_converted,
  household_conversion_ind AS household_converted,
  hybrid_conversion_ind,
  COUNT(DISTINCT email) AS customer_count

FROM {{ ref('fct_sample_conversions') }}
GROUP BY conversion_ind, household_conversion_ind, hybrid_conversion_ind
ORDER BY conversion_ind, household_conversion_ind
```

**Expected:**
| email_converted | household_converted | hybrid_conversion_ind | customer_count |
|-----------------|---------------------|-----------------------|----------------|
| 0 | 0 | 0 | (X customers) |
| 0 | 1 | 1 | (Y customers - captured by household) |
| 1 | 0 | 1 | (rare edge case) |
| 1 | 1 | 1 | (Z customers - both methods agree) |

---

## Known Limitations

### Limitation 1: Address Quality Dependency
**Issue:** Household identification accuracy depends on address data quality
**Impact:** Typos, inconsistent formatting, or incorrect addresses can cause:
- False negatives (same household split into multiple household_ids)
- False positives (different households merged into one household_id, rare)

**Mitigation:**
- Address normalization handles most formatting variations
- Recommend periodic review of multi-email households for false positives
- Future enhancement: integrate address verification API (SmartyStreets, USPS)

---

### Limitation 2: P.O. Boxes and Business Addresses
**Issue:** P.O. boxes and business addresses can aggregate unrelated customers
**Impact:** Multiple unrelated customers using same business address appear as one household

**Mitigation:**
- Currently accepted as business requirement (commercial customers share addresses)
- Can filter to `store = 'regular'` to exclude commercial orders from household analysis
- Future enhancement: flag known commercial/business addresses

---

### Limitation 3: Moved Customers
**Issue:** Customers who move addresses between sample and product orders won't be linked
**Impact:** Household conversion tracking misses these conversions

**Mitigation:**
- No technical solution without address change tracking
- Assume minority of customers (most people don't move within 120-day conversion window)
- Could add "customer lifetime addresses" tracking in future

---

### Limitation 4: International Addresses
**Issue:** Address normalization logic is US-centric (ZIP code formatting, abbreviations)
**Impact:** International addresses may not normalize consistently

**Mitigation:**
- Current implementation handles US and international differently (see `normalized_zip` logic)
- For international expansion, extend normalization logic per country

---

## Model Dependencies

```
stg_shopify__orders (updated to include address fields)
       ↓
int_household_identification (NEW)
       ↓
int_order_classification
       ↓
int_customer_funnel (enhanced with household metrics)
       ↓
fct_sample_conversions (enhanced with household metrics)
```

**Breaking Changes:** None
- All original email-based fields retained
- Household fields are additive (new columns)
- Existing dashboards and queries continue to work unchanged

---

## Testing & Validation Checklist

- [x] Address normalization produces consistent results for similar addresses
- [x] Household_id is stable (deterministic hash)
- [x] Email-based metrics unchanged (backwards compatibility)
- [x] Hybrid conversion logic correct (email OR household)
- [x] Multi-email households identified correctly
- [x] Conversion window buckets populated correctly
- [x] Schema tests pass (unique, not_null, accepted_values)
- [ ] Reconciliation query: Compare household conversion rate to email-only baseline (run in production)
- [ ] Sigma dashboard: Build prototype household conversion dashboard
- [ ] Stakeholder validation: Review multi-email household examples

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-21 | 1.0 | Initial implementation with shipping address matching (street + ZIP) |

---

## Contact & Questions

For questions about household conversion tracking:
1. Review this document and validation queries
2. Check `ASSUMPTIONS_AND_LIMITATIONS.md` for other conversion tracking considerations
3. Run validation queries in `analysis/` directory (to be created)
4. Reference `business_rules.md` section 9 (customer identification) and section 12 (conversion tracking)
