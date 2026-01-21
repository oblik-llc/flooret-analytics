{{
    config(
        materialized='table',
        cluster_by=['sku', 'store', 'line_item_type']
    )
}}

with

order_lines as (
    select * from {{ ref('fct_order_lines') }}
),

weekly_product_sales as (
    select
        date_trunc(order_date, week) as week_start_date,
        sku,
        title,
        color,
        line_item_type,
        store,

        -- Volume metrics
        count(distinct order_id) as order_count,
        sum(quantity) as total_quantity,
        count(distinct order_line_id) as line_item_count,

        -- Revenue metrics
        sum(line_total) as total_revenue,
        avg(price) as average_price,
        sum(total_discount) as total_discount,

        -- Customer metrics
        count(distinct email) as unique_customers,
        count(distinct case when is_new_customer = 1 then email end) as new_customers,
        count(distinct case when is_returning_customer = 1 then email end) as returning_customers,

        -- Conversion metrics (for products purchased after sampling)
        sum(is_converted_purchase) as converted_purchases,
        avg(case when days_from_sample_to_purchase is not null then days_from_sample_to_purchase end) as avg_days_from_sample

    from order_lines
    group by 1, 2, 3, 4, 5, 6
),

final as (
    select
        *,

        -- Date dimensions
        extract(year from week_start_date) as year,
        extract(month from week_start_date) as month,
        extract(quarter from week_start_date) as quarter,
        date_trunc(week_start_date, month) as month_start_date,

        -- Calculated metrics
        case when order_count > 0 then round(total_revenue / order_count, 2) else 0 end as revenue_per_order,
        case when unique_customers > 0 then round(total_revenue / unique_customers, 2) else 0 end as revenue_per_customer,
        case when total_quantity > 0 then round(total_revenue / total_quantity, 2) else 0 end as revenue_per_unit,
        case when total_revenue > 0 then round(total_discount / total_revenue * 100, 2) else 0 end as discount_rate,
        case when line_item_count > 0 then round(cast(converted_purchases as float64) / line_item_count * 100, 2) else 0 end as conversion_rate

    from weekly_product_sales
)

select * from final
