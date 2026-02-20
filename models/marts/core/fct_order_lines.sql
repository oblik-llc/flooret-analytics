{{
    config(
        materialized='table',
        cluster_by=['sku', 'line_item_type', 'store', 'color']
    )
}}

with

order_lines as (
    select * from {{ ref('stg_shopify__order_lines') }}
),

orders as (
    select * from {{ ref('fct_orders') }}
),

final as (
    select
        -- Primary keys
        lines.order_line_id,
        lines.order_id,
        lines.product_id,
        lines.variant_id,

        -- Order context (from fct_orders)
        orders.email,
        orders.processed_at,
        orders.order_date,
        orders.order_year,
        orders.order_month,
        orders.order_quarter,
        orders.store,
        orders.salesperson,

        -- Line item details
        lines.sku,
        lines.title,
        lines.line_item_name,
        lines.vendor,
        lines.variant_title,

        -- Line item classification
        lines.line_item_type,
        lines.sample_type,
        lines.color,

        -- Quantity & pricing
        lines.quantity,
        lines.price,
        lines.line_total,
        lines.total_discount,

        -- Quantity by type
        lines.sample_quantity,
        lines.product_quantity,
        lines.accessories_quantity,

        -- Revenue by type
        lines.sample_revenue,
        lines.product_revenue,
        lines.accessories_revenue,

        -- Metadata
        lines.is_gift_card,
        lines.is_taxable,
        lines.is_shipping_required,
        lines.fulfillment_status,

        -- Order context (for filtering and analysis)
        orders.order_type,
        orders.is_product_order,
        orders.is_sample_order,
        orders.customer_status,
        orders.is_new_customer,
        orders.is_returning_customer,

        -- Customer funnel context
        orders.first_sample_order_date,
        orders.first_product_order_date,
        orders.days_to_order,
        orders.sample_order_type,

        -- Lifetime metrics (order-level at time of line item)
        orders.lifetime_product_orders,
        orders.lifetime_product_revenue,
        orders.lifetime_total_orders,
        orders.lifetime_total_revenue,

        -- Location (for regional analysis)
        orders.shipping_state,
        orders.shipping_state_code,
        orders.shipping_address_city,

        -- Conversion flags (did this line item convert from sample to purchase?)
        case
            when orders.is_product_order = 1
                and orders.first_sample_order_date is not null
                and orders.order_date > orders.first_sample_order_date
            then 1 else 0
        end as is_converted_purchase,

        -- Days from sample to this purchase (if applicable)
        case
            when orders.is_product_order = 1
                and orders.first_sample_order_date is not null
            then date_diff(orders.order_date, orders.first_sample_order_date, day)
            else null
        end as days_from_sample_to_purchase

    from order_lines as lines
    inner join orders
        on lines.order_id = orders.order_id
        and lines.store = orders.store
)

select * from final
