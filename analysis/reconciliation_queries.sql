-- Reconciliation Queries for Sprint 2 Validation
-- Compare dbt models against existing analysis tables
-- Run these after `dbt run` to validate metrics match

-- ============================================================================
-- 1. fct_sample_conversions vs analysis.flooret_funnel
-- ============================================================================

-- Row count comparison
SELECT
  'dbt fct_sample_conversions' AS source,
  COUNT(*) AS row_count
FROM {{ ref('fct_sample_conversions') }}
UNION ALL
SELECT
  'analysis.flooret_funnel' AS source,
  COUNT(*) AS row_count
FROM `bigcommerce-313718.analysis.flooret_funnel`;

-- Key metrics comparison
WITH dbt_metrics AS (
  SELECT
    COUNT(DISTINCT email) AS total_customers,
    COUNT(DISTINCT CASE WHEN first_sample_order_date IS NOT NULL THEN email END) AS customers_with_samples,
    COUNT(DISTINCT CASE WHEN conversion_ind = 1 THEN email END) AS customers_converted,
    ROUND(AVG(days_to_order), 2) AS avg_days_to_order,
    COUNT(DISTINCT CASE WHEN converted_within_15d = 1 THEN email END) AS converted_15d,
    COUNT(DISTINCT CASE WHEN converted_within_30d = 1 THEN email END) AS converted_30d,
    COUNT(DISTINCT CASE WHEN converted_within_60d = 1 THEN email END) AS converted_60d,
    COUNT(DISTINCT CASE WHEN converted_within_120d = 1 THEN email END) AS converted_120d
  FROM {{ ref('fct_sample_conversions') }}
),
analysis_metrics AS (
  SELECT
    COUNT(DISTINCT customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN first_sample_order_date IS NOT NULL THEN customer_id END) AS customers_with_samples,
    -- Note: conversion field may vary in analysis table, adjust as needed
    COUNT(DISTINCT CASE WHEN first_product_order_date IS NOT NULL THEN customer_id END) AS customers_converted,
    ROUND(AVG(days_to_order), 2) AS avg_days_to_order,
    -- Note: conversion window fields may not exist in analysis table
    NULL AS converted_15d,
    NULL AS converted_30d,
    NULL AS converted_60d,
    NULL AS converted_120d
  FROM `bigcommerce-313718.analysis.flooret_funnel`
)
SELECT
  'dbt' AS source,
  total_customers,
  customers_with_samples,
  customers_converted,
  avg_days_to_order,
  converted_15d,
  converted_30d,
  converted_60d,
  converted_120d
FROM dbt_metrics
UNION ALL
SELECT
  'analysis' AS source,
  total_customers,
  customers_with_samples,
  customers_converted,
  avg_days_to_order,
  converted_15d,
  converted_30d,
  converted_60d,
  converted_120d
FROM analysis_metrics;

-- Conversion rate by sample order type
SELECT
  'dbt' AS source,
  sample_order_type,
  COUNT(*) AS customers,
  SUM(conversion_ind) AS converted,
  ROUND(SUM(conversion_ind) / COUNT(*) * 100, 2) AS conversion_rate_pct
FROM {{ ref('fct_sample_conversions') }}
GROUP BY 2
UNION ALL
SELECT
  'analysis' AS source,
  sample_order_type,
  COUNT(*) AS customers,
  COUNT(CASE WHEN first_product_order_date IS NOT NULL THEN 1 END) AS converted,
  ROUND(COUNT(CASE WHEN first_product_order_date IS NOT NULL THEN 1 END) / COUNT(*) * 100, 2) AS conversion_rate_pct
FROM `bigcommerce-313718.analysis.flooret_funnel`
GROUP BY 2
ORDER BY 1, 2;

-- ============================================================================
-- 2. fct_order_lines vs analysis.flooret_lineitem_sales_cleaned
-- ============================================================================

-- Row count comparison
SELECT
  'dbt fct_order_lines' AS source,
  COUNT(*) AS row_count
FROM {{ ref('fct_order_lines') }}
UNION ALL
SELECT
  'analysis.flooret_lineitem_sales_cleaned' AS source,
  COUNT(*) AS row_count
FROM `bigcommerce-313718.analysis.flooret_lineitem_sales_cleaned`;

-- Line item classification counts
SELECT
  'dbt' AS source,
  line_item_type,
  COUNT(*) AS line_item_count,
  SUM(line_total) AS total_revenue,
  SUM(quantity) AS total_quantity
FROM {{ ref('fct_order_lines') }}
GROUP BY 2
UNION ALL
SELECT
  'analysis' AS source,
  sample_vs_product_text AS line_item_type,
  COUNT(*) AS line_item_count,
  SUM(price * quantity) AS total_revenue,
  SUM(quantity) AS total_quantity
FROM `bigcommerce-313718.analysis.flooret_lineitem_sales_cleaned`
GROUP BY 2
ORDER BY 1, 2;

-- Revenue by product category (if available in analysis table)
SELECT
  'dbt' AS source,
  -- Note: product category not fully implemented yet, will use color as proxy
  color,
  line_item_type,
  COUNT(*) AS line_item_count,
  ROUND(SUM(line_total), 2) AS total_revenue
FROM {{ ref('fct_order_lines') }}
GROUP BY 2, 3
ORDER BY 5 DESC
LIMIT 20;

-- ============================================================================
-- 3. fct_orders vs analysis.flooret_order_only
-- ============================================================================

-- Row count comparison
SELECT
  'dbt fct_orders' AS source,
  COUNT(*) AS row_count
FROM {{ ref('fct_orders') }}
UNION ALL
SELECT
  'analysis.flooret_order_only' AS source,
  COUNT(*) AS row_count
FROM `bigcommerce-313718.analysis.flooret_order_only`;

-- Order classification counts
SELECT
  'dbt' AS source,
  order_type,
  COUNT(*) AS order_count,
  ROUND(SUM(net_sales), 2) AS total_revenue,
  COUNT(DISTINCT email) AS unique_customers
FROM {{ ref('fct_orders') }}
GROUP BY 2
UNION ALL
SELECT
  'analysis' AS source,
  CASE
    WHEN product_order = 1 THEN 'Product Order'
    WHEN sample_order = 1 THEN 'Sample Order'
    ELSE 'Other'
  END AS order_type,
  COUNT(*) AS order_count,
  -- Note: net_sales field may vary, adjust as needed
  ROUND(SUM(COALESCE(net_sales, 0)), 2) AS total_revenue,
  COUNT(DISTINCT email) AS unique_customers
FROM `bigcommerce-313718.analysis.flooret_order_only`
GROUP BY 2
ORDER BY 1, 2;

-- Lifetime product revenue comparison
WITH dbt_lifetime AS (
  SELECT
    email,
    MAX(lifetime_product_revenue) AS lifetime_product_revenue,
    MAX(lifetime_product_orders) AS lifetime_product_orders
  FROM {{ ref('fct_orders') }}
  GROUP BY 1
),
analysis_lifetime AS (
  SELECT
    email,
    MAX(lifetime_product_revenue) AS lifetime_product_revenue,
    MAX(lifetime_product_orders) AS lifetime_product_orders
  FROM `bigcommerce-313718.analysis.flooret_order_only`
  GROUP BY 1
)
SELECT
  'dbt' AS source,
  COUNT(DISTINCT email) AS customers,
  ROUND(AVG(lifetime_product_revenue), 2) AS avg_lifetime_revenue,
  ROUND(AVG(lifetime_product_orders), 2) AS avg_lifetime_orders
FROM dbt_lifetime
UNION ALL
SELECT
  'analysis' AS source,
  COUNT(DISTINCT email) AS customers,
  ROUND(AVG(lifetime_product_revenue), 2) AS avg_lifetime_revenue,
  ROUND(AVG(lifetime_product_orders), 2) AS avg_lifetime_orders
FROM analysis_lifetime;

-- Customer status distribution
SELECT
  'dbt' AS source,
  customer_status,
  COUNT(*) AS order_count,
  ROUND(SUM(net_sales), 2) AS total_revenue
FROM {{ ref('fct_orders') }}
GROUP BY 2
ORDER BY 1, 4 DESC;

-- ============================================================================
-- 4. dim_customers validation
-- ============================================================================

-- Customer dimension row count
SELECT
  'dbt dim_customers' AS source,
  COUNT(*) AS row_count
FROM {{ ref('dim_customers') }};

-- Customer segment distribution
SELECT
  customer_segment,
  COUNT(*) AS customer_count,
  ROUND(AVG(lifetime_total_revenue), 2) AS avg_lifetime_revenue,
  ROUND(AVG(lifetime_total_orders), 2) AS avg_lifetime_orders
FROM {{ ref('dim_customers') }}
GROUP BY 1
ORDER BY 2 DESC;

-- Customer group distribution
SELECT
  customer_group,
  COUNT(*) AS customer_count,
  ROUND(AVG(lifetime_product_revenue), 2) AS avg_product_revenue,
  SUM(CASE WHEN conversion_ind = 1 THEN 1 ELSE 0 END) AS converted_customers,
  ROUND(SUM(CASE WHEN conversion_ind = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS conversion_rate_pct
FROM {{ ref('dim_customers') }}
WHERE first_sample_order_date IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC;

-- ============================================================================
-- 5. Cross-model consistency checks
-- ============================================================================

-- Ensure all orders have matching line items
SELECT
  'Orders without line items' AS check_name,
  COUNT(*) AS count
FROM {{ ref('fct_orders') }} o
LEFT JOIN {{ ref('fct_order_lines') }} l ON o.order_id = l.order_id
WHERE l.order_line_id IS NULL;

-- Ensure all customers in fct_orders exist in dim_customers
SELECT
  'Orders with missing customers' AS check_name,
  COUNT(DISTINCT o.email) AS count
FROM {{ ref('fct_orders') }} o
LEFT JOIN {{ ref('dim_customers') }} c ON o.email = c.email
WHERE c.email IS NULL;

-- Ensure fct_sample_conversions emails exist in dim_customers
SELECT
  'Sample conversions with missing customers' AS check_name,
  COUNT(DISTINCT s.email) AS count
FROM {{ ref('fct_sample_conversions') }} s
LEFT JOIN {{ ref('dim_customers') }} c ON s.email = c.email
WHERE c.email IS NULL;

-- ============================================================================
-- 6. Data quality checks
-- ============================================================================

-- Check for negative revenue
SELECT
  'Orders with negative revenue' AS check_name,
  COUNT(*) AS count
FROM {{ ref('fct_orders') }}
WHERE net_sales < 0;

-- Check for orphaned lifetime metrics
SELECT
  'Orders where lifetime < current order' AS check_name,
  COUNT(*) AS count
FROM {{ ref('fct_orders') }}
WHERE product_revenue > lifetime_product_revenue;

-- Check for conversion logic consistency
SELECT
  'Conversions where first_sample > first_product' AS check_name,
  COUNT(*) AS count
FROM {{ ref('fct_sample_conversions') }}
WHERE first_sample_order_date > first_product_order_date;

-- ============================================================================
-- ACCEPTANCE CRITERIA FOR SPRINT 2
-- ============================================================================
-- Run all queries above and verify:
-- 1. Row counts match within 1% (dbt vs analysis tables)
-- 2. Key metrics (conversion rates, revenue totals) match within 1%
-- 3. Classification distributions are similar
-- 4. All cross-model consistency checks return 0
-- 5. All data quality checks return 0
-- ============================================================================
