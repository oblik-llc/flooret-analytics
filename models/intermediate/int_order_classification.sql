{{
    config(
        materialized='view'
    )
}}

with

order_lines as (
    select * from {{ ref('stg_shopify__order_lines') }}
),

orders as (
    select * from {{ ref('stg_shopify__orders') }}
),

-- Aggregate line items to order level
order_line_agg as (
    select
        order_id,

        -- Quantity aggregations by type
        sum(sample_quantity) as sample_quantity,
        sum(product_quantity) as product_quantity,
        sum(accessories_quantity) as accessories_quantity,
        sum(quantity) as total_quantity,

        -- Revenue aggregations by type
        sum(sample_revenue) as sample_revenue,
        sum(product_revenue) as product_revenue,
        sum(accessories_revenue) as accessories_revenue,
        sum(line_total) as total_line_items_revenue,

        -- Line item counts
        count(*) as line_item_count,
        count(distinct sku) as distinct_sku_count,

        -- Sample type breakdown
        sum(case when sample_type = 'Sample - Cut' then sample_quantity else 0 end) as cut_sample_quantity,
        sum(case when sample_type = 'Sample - Plank' then sample_quantity else 0 end) as plank_sample_quantity,

        -- Product category breakdown (for sample order type classification later)
        count(distinct case when sample_quantity > 0 then color end) as sample_color_count,
        count(distinct case when product_quantity > 0 then color end) as product_color_count

    from order_lines
    group by 1
),

-- Join with order header
orders_enriched as (
    select
        orders.order_id,
        orders.email,
        orders.customer_id,
        orders.processed_at,
        orders.order_date,
        orders.order_year,
        orders.order_month,
        orders.order_quarter,
        orders.store,
        orders.product_price_threshold,
        orders.default_salesperson,
        orders.salesperson,

        -- Order monetary fields
        orders.subtotal_price,
        orders.total_price,
        orders.total_discounts,
        orders.total_tax,
        orders.total_tip_received,

        -- Refund fields
        orders.refund_subtotal,
        orders.refund_total_tax,
        orders.order_adjustment_amount,

        -- Order metadata
        orders.order_name,
        orders.order_number,
        orders.note,
        orders.source_name,
        orders.financial_status,
        orders.fulfillment_status,
        orders.cancel_reason,

        -- Location
        orders.billing_state,
        orders.billing_state_code,
        orders.billing_address_city,
        orders.billing_address_zip,
        orders.billing_address_country,
        orders.billing_address_country_code,
        orders.shipping_state,
        orders.shipping_state_code,
        orders.shipping_address_city,
        orders.shipping_address_zip,
        orders.shipping_address_country,
        orders.shipping_address_country_code,

        -- Line item aggregations
        coalesce(agg.sample_quantity, 0) as sample_quantity,
        coalesce(agg.product_quantity, 0) as product_quantity,
        coalesce(agg.accessories_quantity, 0) as accessories_quantity,
        coalesce(agg.total_quantity, 0) as total_quantity,
        coalesce(agg.sample_revenue, 0) as sample_revenue,
        coalesce(agg.product_revenue, 0) as product_revenue,
        coalesce(agg.accessories_revenue, 0) as accessories_revenue,
        coalesce(agg.total_line_items_revenue, 0) as total_line_items_revenue,
        coalesce(agg.line_item_count, 0) as line_item_count,
        coalesce(agg.distinct_sku_count, 0) as distinct_sku_count,
        coalesce(agg.cut_sample_quantity, 0) as cut_sample_quantity,
        coalesce(agg.plank_sample_quantity, 0) as plank_sample_quantity,
        coalesce(agg.sample_color_count, 0) as sample_color_count,
        coalesce(agg.product_color_count, 0) as product_color_count

    from orders
    left join order_line_agg as agg
        on orders.order_id = agg.order_id
),

final as (
    select
        *,

        -- Order Classification (business_rules.md section 7)
        -- Product Order: product_quantity > 0 AND net_sales > $250
        -- Sample Order: sample_quantity > 0 AND product_quantity = 0
        -- Accessory Only: accessories_quantity > 0 AND no samples/products
        case
            when product_quantity > 0 and subtotal_price > 250 then 'Product Order'
            when sample_quantity > 0 and product_quantity = 0 then 'Sample Order'
            when accessories_quantity > 0 and sample_quantity = 0 and product_quantity = 0 then 'Accessory Only'
            else 'Other'
        end as order_type,

        -- Order type boolean flags (for easier filtering and aggregation)
        case when product_quantity > 0 and subtotal_price > 250 then 1 else 0 end as is_product_order,
        case when sample_quantity > 0 and product_quantity = 0 then 1 else 0 end as is_sample_order,
        case when accessories_quantity > 0 and sample_quantity = 0 and product_quantity = 0 then 1 else 0 end as is_accessory_only,

        -- Sample type flags (for funnel analysis)
        case when cut_sample_quantity > 0 then 1 else 0 end as has_cut_samples,
        case when plank_sample_quantity > 0 then 1 else 0 end as has_plank_samples,

        -- Net sales (subtotal_price minus refund subtotals)
        subtotal_price - refund_subtotal as net_sales,

        -- Average order value metrics
        case when line_item_count > 0 then subtotal_price / line_item_count else 0 end as avg_line_item_value,
        case when total_quantity > 0 then subtotal_price / total_quantity else 0 end as avg_unit_price,

        -- Discount metrics
        case when subtotal_price > 0 then total_discounts / subtotal_price else 0 end as discount_rate,
        case when distinct_sku_count > 0 then total_discounts / distinct_sku_count else 0 end as line_item_discount

    from orders_enriched
)

select * from final
