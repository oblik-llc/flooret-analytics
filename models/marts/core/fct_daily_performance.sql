{{
    config(
        materialized='table',
        partition_by={
            "field": "date_day",
            "data_type": "date",
            "granularity": "day"
        },
        cluster_by=['store']
    )
}}

with

-- Daily orders aggregation
daily_orders as (
    select
        order_date as date_day,
        store,

        -- Order counts
        count(distinct order_id) as total_orders,
        sum(is_product_order) as product_orders,
        sum(is_sample_order) as sample_orders,
        sum(is_accessory_only) as accessory_orders,

        -- Customer counts
        count(distinct email) as total_customers,
        count(distinct case when is_new_customer = 1 then email end) as new_customers,
        count(distinct case when is_returning_customer = 1 then email end) as returning_customers,

        -- Revenue metrics
        sum(net_sales) as total_revenue,
        sum(case when is_product_order = 1 then net_sales else 0 end) as product_revenue,
        sum(case when is_sample_order = 1 then net_sales else 0 end) as sample_revenue,
        sum(total_discounts) as total_discounts,

        -- Quantity metrics
        sum(product_quantity) as total_product_quantity,
        sum(sample_quantity) as total_sample_quantity,
        sum(accessories_quantity) as total_accessories_quantity,

        -- AOV
        avg(net_sales) as average_order_value,
        avg(case when is_product_order = 1 then net_sales end) as average_product_order_value

    from {{ ref('fct_orders') }}
    group by 1, 2
),

-- Daily ad spend
daily_ad_spend as (
    select
        date_day,

        sum(spend) as total_ad_spend,
        sum(case when channel = 'Facebook' then spend else 0 end) as facebook_spend,
        sum(case when channel = 'Google' then spend else 0 end) as google_spend,

        sum(conversions) as total_ad_conversions,
        sum(conversions_value) as total_ad_conversion_value,

        sum(clicks) as total_ad_clicks,
        sum(impressions) as total_ad_impressions

    from {{ ref('fct_ad_performance') }}
    group by 1
),

-- Combine into daily performance
combined as (
    select
        orders.date_day,
        orders.store,

        -- Order metrics
        orders.total_orders,
        orders.product_orders,
        orders.sample_orders,
        orders.accessory_orders,

        -- Customer metrics
        orders.total_customers,
        orders.new_customers,
        orders.returning_customers,

        -- Revenue metrics
        orders.total_revenue,
        orders.product_revenue,
        orders.sample_revenue,
        orders.total_discounts,
        orders.average_order_value,
        orders.average_product_order_value,

        -- Quantity metrics
        orders.total_product_quantity,
        orders.total_sample_quantity,
        orders.total_accessories_quantity,

        -- Ad spend metrics (same across stores)
        coalesce(ads.total_ad_spend, 0) as total_ad_spend,
        coalesce(ads.facebook_spend, 0) as facebook_spend,
        coalesce(ads.google_spend, 0) as google_spend,
        coalesce(ads.total_ad_conversions, 0) as total_ad_conversions,
        coalesce(ads.total_ad_conversion_value, 0) as total_ad_conversion_value,
        coalesce(ads.total_ad_clicks, 0) as total_ad_clicks,
        coalesce(ads.total_ad_impressions, 0) as total_ad_impressions

    from daily_orders as orders
    left join daily_ad_spend as ads
        on orders.date_day = ads.date_day
),

final as (
    select
        *,

        -- Date dimensions
        extract(year from date_day) as year,
        extract(month from date_day) as month,
        extract(quarter from date_day) as quarter,
        extract(dayofweek from date_day) as day_of_week,
        format_date('%A', date_day) as day_name,
        date_trunc(date_day, week) as week_start_date,
        date_trunc(date_day, month) as month_start_date,

        -- Calculated metrics
        case
            when new_customers > 0
            then round(total_ad_spend / new_customers, 2)
            else 0
        end as cac,

        case
            when total_ad_spend > 0
            then round(total_revenue / total_ad_spend, 2)
            else 0
        end as roas,

        case
            when total_orders > 0
            then round(cast(product_orders as float64) / total_orders * 100, 2)
            else 0
        end as product_order_rate,

        case
            when total_customers > 0
            then round(cast(new_customers as float64) / total_customers * 100, 2)
            else 0
        end as new_customer_rate,

        -- Revenue - Ad Spend (simple unit economics without COGS)
        total_revenue - total_ad_spend as contribution_margin_excl_cogs

    from combined
)

select * from final
