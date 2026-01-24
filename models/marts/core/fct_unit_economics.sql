{{
    config(
        materialized='table',
        partition_by={"field": "order_date", "data_type": "date", "granularity": "day"},
        cluster_by=['store', 'order_id']
    )
}}

/*
    Order-Level Unit Economics

    Purpose:
        Calculates order-level profitability with available cost data.

    Grain: order_id (order level)

    LIMITATIONS:
        ❌ COGS not available
        ❌ Shipping costs cannot be linked to orders (no order_id in Freightview)

    Available:
        ✅ Ad spend allocation (to new customers)
        ✅ Discounts
*/

with order_base as (
    select
        order_id,
        email,
        order_date,
        store,
        order_type,
        subtotal_price as gross_revenue,
        total_discounts as discount_amount,
        subtotal_price - total_discounts as net_sales,
        total_tax,
        customer_status,
        lifetime_product_revenue,
        salesperson,
        shipping_state,
        shipping_address_country

    from {{ ref('fct_orders') }}
    where order_type = 'Product Order'
),

daily_ad_spend as (
    select
        date_day,
        store,
        sum(total_ad_spend) as total_ad_spend,
        sum(new_customers) as new_customers

    from {{ ref('fct_daily_performance') }}
    where new_customers > 0
    group by date_day, store
),

ad_spend_allocation as (
    select
        o.order_id,
        o.email,
        o.order_date,
        o.store,
        o.customer_status,
        case
            when o.customer_status in ('New Customer', 'New Customer Sample')
                and a.new_customers > 0
            then round(a.total_ad_spend / a.new_customers, 2)
            else 0
        end as allocated_ad_spend

    from order_base o
    left join daily_ad_spend a
        on o.order_date = a.date_day
        and o.store = a.store
),

final as (
    select
        o.order_id,
        o.email,
        o.order_date,
        o.store,
        o.order_type,
        o.customer_status,
        o.salesperson,
        o.shipping_state,
        o.shipping_address_country,

        round(o.gross_revenue, 2) as gross_revenue,
        round(o.discount_amount, 2) as discount_amount,
        round(o.net_sales, 2) as net_sales,

        case when o.gross_revenue > 0
            then round(o.discount_amount / o.gross_revenue * 100, 2)
            else 0
        end as discount_rate_pct,

        round(coalesce(a.allocated_ad_spend, 0), 2) as allocated_ad_spend,

        round(
            o.net_sales - coalesce(a.allocated_ad_spend, 0),
            2
        ) as contribution_margin_before_cogs,

        case when o.net_sales > 0
            then round(
                (o.net_sales - coalesce(a.allocated_ad_spend, 0))
                / o.net_sales * 100,
                2
            )
            else 0
        end as contribution_margin_pct,

        case when o.net_sales > 0
            then round(coalesce(a.allocated_ad_spend, 0) / o.net_sales * 100, 2)
            else 0
        end as ad_spend_pct,

        round(o.lifetime_product_revenue, 2) as lifetime_product_revenue

    from order_base o
    left join ad_spend_allocation a on o.order_id = a.order_id
)

select * from final
