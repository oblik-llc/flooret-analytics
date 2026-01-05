# Florret Business Rules

Extracted from analyst's BigQuery scheduled queries. These rules define how raw Shopify data is transformed into business metrics.

---

## 1. Line Item Classification

Every line item is classified into one of three categories based on title, SKU, and price.

### Sample
A line item is a **Sample** if ANY of the following are true:
- `title` contains 'Cut'
- `title` contains 'Sample'
- `title` contains 'Plank'
- `sku` contains 'CUT'
- `sku` contains 'FULL'

### Product
A line item is a **Product** if:
- `price > 55` (regular Shopify) OR `price > 40` (commercial Shopify)
- AND `title` does NOT contain 'Nosing'
- AND it doesn't qualify as a Sample (above rules)

### Accessories/Other
Everything else that doesn't qualify as Sample or Product.

---

## 2. Sample Type Classification

Samples are further classified into Cut vs Plank:

| Sample Type | Rule |
|-------------|------|
| Sample - Cut | `title` contains 'Cut' OR `sku` contains 'CUT' OR `title` contains 'Sample' |
| Sample - Plank | `title` contains 'Plank' OR `sku` contains 'FULL' |

---

## 3. Product Category

Product category is derived from SKU patterns. This is a two-step process.

### Step 1: Derive `category_shopify` from SKU

| Condition | Result |
|-----------|--------|
| `product_type = 'lvp'` AND item is Product | `'lvp-' + last segment of SKU after final '-'` |
| `product_type = 'lvp'` AND item is Sample | `'lvp-' + extract B/C/S from SKU pattern '[^-]-(B|C|S)-[^-]'` |
| Item is Product (non-lvp) | `'lvp-' + last segment of SKU` |
| Item is Sample AND `sku` contains '7-CUT' | `'lvp-7T'` |
| Item is Sample (non-lvp) | `'lvp-' + extract B/C/S from SKU pattern` |
| Else | `product_type` |

### Step 2: Map `category_shopify` to Product Category

| category_shopify | Product Category |
|------------------|------------------|
| `lvp-S` | Signature |
| `lvp-7210` | Signature |
| `lvp-B` | Base |
| `lvp-4805` | Base |
| `lvp-C` | Craftsman |
| `lvp-7` | Silvan Hardwood |
| `lvp-7T` | Silvan Hardwood |
| Everything else | Other |

### Product Lines
The company has the following product lines:
- **Base** - Entry-level LVP flooring
- **Signature** - Mid-tier LVP flooring
- **Craftsman** - Premium LVP flooring
- **Silvan Hardwood** - Hardwood flooring line
- **Iona** - Additional product line (mentioned in pivots but not in category logic)
- **Other** - Catch-all for accessories, nosing, etc.

---

## 4. Customer Group

Derived from customer `tags` field:

| Customer Group | Rule |
|----------------|------|
| Retail | `tags` contains 'Retail' OR `tags` contains 'Guest' OR `tags` is empty |
| Trade Rewards | `tags` contains 'Trade' OR 'Legacy TR' OR 'Partner Plus' AND `tags` does NOT contain 'Pending' |
| Pending Trade Rewards | `tags` contains 'Pending' |
| Default | Retail |

---

## 5. Customer Type

Extracted from customer `tags` using regex:
```
regexp_extract(tags, r'Customer Type: (.*?),')
```
Default: `'DTC'` (Direct to Consumer)

---

## 6. Salesperson

Extracted from order `tags` using regex:
```
regexp_extract(tags, r'Salesperson: (.*?),')
```
Default: `'DTC'` for regular orders, `'Commercial'` for commercial orders

---

## 7. Order Classification

At the order level (after line item aggregation):

| Order Type | Rule |
|------------|------|
| Product Order | `product_quantity > 0` AND `net_sales > 250` |
| Sample Order | `sample_quantity > 0` AND `product_quantity = 0` |
| Accessory Only Order | `accessories_quantity > 0` AND `sample_quantity = 0` AND `product_quantity = 0` |

**Note:** The $250 threshold ensures small product add-ons to sample orders don't count as product orders.

---

## 8. Customer Status (New vs Returning)

Determined per order based on customer's order history:

| Status | Rule |
|--------|------|
| New Customer | `order_date = first_product_order_date` |
| New Customer Sample | `order_date = first_sample_order_date` |
| Returning Sample | `order_date > first_sample_order_date` AND `sample_quantity > 0` AND `product_quantity = 0` |
| Returning Customer | `order_date > first_product_order_date` AND `product_quantity > 0` |

---

## 9. First Order Date Definitions

These are calculated per customer using window functions:

| Metric | Definition |
|--------|------------|
| `first_sample_order_date` | MIN of `processed_at` WHERE `sample_quantity > 0` AND `product_quantity = 0` |
| `first_product_order_date` | MIN of `processed_at` WHERE `product_quantity > 0` |
| `first_cut_order_date` | MIN of `processed_at` WHERE `sample_quantity > 0` AND `cut_vs_plank_vs_product_text = 'Sample - Cut'` |
| `first_plank_order_date` | MIN of `processed_at` WHERE `sample_quantity > 0` AND `cut_vs_plank_vs_product_text = 'Sample - Plank'` |

---

## 10. Color Extraction

Product color is extracted from the line item title:
```
REGEXP_EXTRACT(title, r'^(.+?)\s')
```
Takes the first word before a space. If no match, uses full title.

---

## 11. Lifetime Metrics

Calculated per customer (partitioned by email):

| Metric | Definition |
|--------|------------|
| `lifetime_product_orders` | SUM of `product_order` flag across all customer orders |
| `lifetime_product_revenue` | SUM of `product_product_price_subtotal` across all customer orders |

---

## 12. Sample-to-Purchase Conversion Metrics

### Days to Order
| Metric | Definition |
|--------|------------|
| `days_to_order` | `DATE_DIFF(first_product_order_date, first_sample_order_date, DAY)` |
| `days_cut_to_order` | `DATE_DIFF(first_product_order_date, first_cut_order_date, DAY)` |
| `days_plank_to_order` | `DATE_DIFF(first_product_order_date, first_plank_order_date, DAY)` |
| `days_cut_to_plank` | `DATE_DIFF(first_plank_order_date, first_cut_order_date, DAY)` |

### Conversion Windows
Orders are bucketed by time from sample to purchase:
- 15 days
- 30 days
- 60 days
- 120 days

### Conversion Indicators
| Metric | Definition |
|--------|------------|
| `conversion_ind` | 1 if customer ever placed a product order (MAX of `product_order_ind` per customer) |
| `color_conversion` | 1 if `product_quantity > 0` AND `processed_at > first_sample_order_per_color` |

---

## 13. Sample Order Type

Classifies customers by which product categories they sampled (before purchasing):

| Sample Order Type | Rule |
|-------------------|------|
| Base Sample Only | Only Base samples, no other categories |
| Signature Sample Only | Only Signature samples |
| Craftsman Sample Only | Only Craftsman samples |
| Silvan Sample Only | Only Silvan samples |
| Base and Signature Sample Only | Both Base and Signature, no others |
| (other combinations) | Various multi-category combinations |
| Other | Everything else |

---

## 14. Cohort Analysis Definitions

| Metric | Definition |
|--------|------------|
| `cohort_month` | `first_sample_order_date` truncated to first of month |
| `order_month` | `order_date` truncated to first of month |
| `retention_months` | `DATE_DIFF(order_date, first_sample_order_date, MONTH) + 1` |
| `first_month_count` | Count of customers in cohort's first month |
| `first_month_sales` | Sum of sales in cohort's first month |
| `count_retention` | `customer_count / first_month_count` |
| `sales_retention` | `customer_sales / first_month_sales` |

---

## 15. Pricing Fields

| Field | Definition |
|-------|------------|
| `subtotal_price` | Order subtotal before tax |
| `subtotal_plus_tax` | `subtotal_price + total_tax` |
| `total_excl_tax` | `total_price - total_tax` |
| `total_price` | Order total including tax |
| `total_discounts` | Sum of discounts applied |
| `net_sales` | `subtotal_price` (used interchangeably) |
| `line_item_discount` | `total_discounts / count of distinct SKUs in order` |

---

## 16. Quantity Breakdowns

At line item level:
| Field | Definition |
|-------|------------|
| `sample_quantity` | `quantity` if item is Sample, else 0 |
| `product_quantity` | `quantity` if item is Product, else 0 |
| `accessories_quantity` | `quantity` if item is Accessories/Other, else 0 |

At order level (aggregated):
| Field | Definition |
|-------|------------|
| `sample_quantity` | SUM of sample quantities |
| `sample_type_count` | COUNT DISTINCT of product categories where `sample_quantity > 0` |
| `product_quantity` | SUM of product quantities |
| `accessories_quantity` | SUM of accessories quantities |

---

## 17. Revenue Breakdowns

| Field | Definition |
|-------|------------|
| `sample_total_price` | `price * quantity` if Sample |
| `product_total_price` | `price * quantity` if Product |
| `accessories_total_price` | `price * quantity` if Accessories |
| `sample_product_price_subtotal` | SUM of `sample_total_price` at order level |
| `product_product_price_subtotal` | SUM of `product_total_price` at order level |
| `accessories_product_price_subtotal` | SUM of `accessories_total_price` at order level |

---

## 18. Data Exclusions

The analyst applies these filters in various queries:

| Exclusion | Reason |
|-----------|--------|
| `email NOT LIKE '%amazon%'` | Exclude Amazon marketplace orders |
| `first_sample_order_date > '2020-12-31'` | Exclude pre-2021 sample orders for funnel analysis |
| `email IS NOT NULL` | Exclude guest checkouts for customer-level analysis |
| `customer_id IS NOT NULL` | Exclude orders without customer linkage |

---

## 19. Timestamp Handling

- `processed_at` is converted to Pacific time: `DATETIME(processed_at, "America/Los_Angeles")`
- Dates are extracted as `DATE(processed_at)` after timezone conversion
- `created_at` exists but `processed_at` is the primary order date field

---

## 20. Two Shopify Stores

The analyst maintains separate logic for two stores:

| Store | Source Tables | Price Threshold | Default Salesperson |
|-------|---------------|-----------------|---------------------|
| Regular Shopify | `bigcommerce-313718.shopify.*` | $55 | DTC |
| Commercial Shopify | `bigcommerce-313718.shopify_commercial_v2.*` | $40 | Commercial |

The business logic is identical except for these differences.

---

## Notes for dbt Implementation

1. **Customer identifier:** The analyst uses `email` (lowercased) as the primary customer identifier for lifetime calculations, not `customer_id`. This handles guest checkouts and cross-device behavior.

2. **Product category is critical:** Many downstream metrics depend on correct product category assignment. The SKU regex patterns are specific to Florret's naming conventions.

3. **Sample-to-purchase funnel is core:** Much of the analysis focuses on tracking customers from sample orders to product purchases. The `first_*_order_date` fields are foundational.

4. **Two stores, one model:** Consider whether to union the two Shopify stores early (with a `store` dimension) or keep them separate throughout.
