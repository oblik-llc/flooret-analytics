{{
    config(
        materialized='table',
        partition_by={
            "field": "order_date",
            "data_type": "date",
            "granularity": "day"
        },
        cluster_by=['email', 'store', 'order_type']
    )
}}

with

orders_with_lifetime as (
    select * from {{ ref('int_customer_lifetime_metrics') }}
),

customer_funnel as (
    select * from {{ ref('int_customer_funnel') }}
),

final as (
    select
        -- Primary keys
        orders.order_id,
        orders.email,
        orders.customer_id,

        -- Timestamps
        orders.processed_at,
        orders.order_date,
        orders.order_year,
        orders.order_month,
        orders.order_quarter,

        -- Store & sales rep
        orders.store,
        orders.salesperson,

        -- Order classification
        orders.order_type,
        orders.is_product_order,
        orders.is_sample_order,
        orders.is_accessory_only,

        -- Order status
        orders.financial_status,
        orders.fulfillment_status,
        orders.cancel_reason,

        -- Revenue metrics
        orders.subtotal_price,
        orders.total_price,
        orders.total_discounts,
        orders.total_tax,
        orders.net_sales,

        -- Discount metrics
        orders.discount_rate,
        orders.line_item_discount,

        -- Quantity metrics
        orders.sample_quantity,
        orders.product_quantity,
        orders.accessories_quantity,
        orders.total_quantity,
        orders.cut_sample_quantity,
        orders.plank_sample_quantity,

        -- Revenue by type
        orders.sample_revenue,
        orders.product_revenue,
        orders.accessories_revenue,
        orders.total_line_items_revenue,

        -- Order metadata
        orders.line_item_count,
        orders.distinct_sku_count,
        orders.sample_color_count,
        orders.product_color_count,

        -- Sample flags
        orders.has_cut_samples,
        orders.has_plank_samples,

        -- Location (shipping for regional analysis)
        orders.shipping_state,
        orders.shipping_state_code,
        orders.shipping_address_city,
        orders.shipping_address_zip,
        orders.shipping_address_country,

        -- Billing location (for tax/fraud analysis)
        orders.billing_state,
        orders.billing_state_code,

        -- Lifetime metrics (from int_customer_lifetime_metrics)
        orders.lifetime_product_orders,
        orders.lifetime_sample_orders,
        orders.lifetime_total_orders,
        orders.lifetime_product_revenue,
        orders.lifetime_sample_revenue,
        orders.lifetime_total_revenue,

        -- Order sequence
        orders.order_sequence_number,
        orders.product_order_sequence_number,
        orders.sample_order_sequence_number,

        -- Customer status flags
        orders.is_first_order,
        orders.is_first_product_order,
        orders.is_first_sample_order,

        -- Lifetime value metrics
        orders.avg_order_value_to_date,
        orders.days_since_first_order,

        -- Customer funnel dates (from int_customer_funnel)
        funnel.first_sample_order_date,
        funnel.first_product_order_date,
        funnel.days_to_order,
        funnel.sample_order_type,

        -- Customer status (business_rules.md section 8)
        case
            when orders.is_first_product_order = 1 then 'New Customer'
            when orders.is_first_sample_order = 1 then 'New Customer Sample'
            when orders.is_sample_order = 1 and orders.order_date > funnel.first_sample_order_date then 'Returning Sample'
            when orders.is_product_order = 1 and orders.order_date > funnel.first_product_order_date then 'Returning Customer'
            else 'Other'
        end as customer_status,

        -- New vs returning flags (for dashboards)
        case when orders.is_first_product_order = 1 then 1 else 0 end as is_new_customer,
        case when orders.is_product_order = 1 and orders.order_date > funnel.first_product_order_date then 1 else 0 end as is_returning_customer

    from orders_with_lifetime as orders
    left join customer_funnel as funnel
        on orders.email = funnel.email
)

select * from final
