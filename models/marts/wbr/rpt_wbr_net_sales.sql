{{
    config(
        materialized='table'
    )
}}

-- WBR Page 2: Net Sales (Weekly + Monthly)
-- Net Sales = subtotal_price (order-level) across ALL order types

with

orders as (
    select * from {{ ref('fct_orders') }}
    where cancel_reason is null
),

-- Weekly net sales (ISO weeks, Monday-Sunday)
weekly as (
    select
        extract(isoyear from order_date) as iso_year,
        extract(isoweek from order_date) as iso_week,
        date_trunc(order_date, isoweek) as week_start,

        sum(net_sales) as net_sales,
        count(distinct order_id) as total_orders,
        count(distinct email) as unique_customers

    from orders
    group by 1, 2, 3
),

weekly_with_comparisons as (
    select
        w.*,

        -- Week-over-week
        lag(w.net_sales) over (order by w.week_start) as prev_week_net_sales,
        safe_divide(
            w.net_sales - lag(w.net_sales) over (order by w.week_start),
            abs(lag(w.net_sales) over (order by w.week_start))
        ) as wow_change_pct,

        -- Year-over-year (same ISO week, prior year)
        yoy.net_sales as prior_year_net_sales,
        safe_divide(
            w.net_sales - yoy.net_sales,
            abs(yoy.net_sales)
        ) as yoy_change_pct

    from weekly as w
    left join weekly as yoy
        on w.iso_week = yoy.iso_week
        and w.iso_year = yoy.iso_year + 1
),

-- Monthly net sales for trailing 12-month view
monthly as (
    select
        date_trunc(order_date, month) as month_start,
        extract(year from order_date) as year,
        extract(month from order_date) as month,

        sum(net_sales) as net_sales,
        count(distinct order_id) as total_orders,
        count(distinct email) as unique_customers

    from orders
    group by 1, 2, 3
),

-- Combine weekly and monthly into a single output with a grain indicator
final as (
    -- Weekly rows
    select
        'weekly' as grain,
        iso_year,
        iso_week,
        week_start as period_start,
        cast(null as date) as month_start,
        net_sales,
        total_orders,
        unique_customers,
        prev_week_net_sales,
        wow_change_pct,
        prior_year_net_sales,
        yoy_change_pct
    from weekly_with_comparisons

    union all

    -- Monthly rows
    select
        'monthly' as grain,
        year as iso_year,
        cast(null as int64) as iso_week,
        cast(null as date) as period_start,
        month_start,
        net_sales,
        total_orders,
        unique_customers,
        cast(null as float64) as prev_week_net_sales,
        cast(null as float64) as wow_change_pct,
        cast(null as float64) as prior_year_net_sales,
        cast(null as float64) as yoy_change_pct
    from monthly
)

select * from final
