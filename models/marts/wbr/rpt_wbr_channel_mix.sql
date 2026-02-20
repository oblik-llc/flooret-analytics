{{
    config(
        materialized='table'
    )
}}

-- WBR Page 3: Sales by Channel
-- Channel attribution: store + salesperson field from order tags
-- DTC (default regular), Commercial (commercial store), MSR/Installer, Ind. Retail

with

orders as (
    select * from {{ ref('fct_orders') }}
    where cancel_reason is null
),

-- Map salesperson to WBR channel
orders_with_channel as (
    select
        *,
        extract(isoyear from order_date) as iso_year,
        extract(isoweek from order_date) as iso_week,
        date_trunc(order_date, isoweek) as week_start,

        -- Channel mapping
        case
            when store = 'commercial' then 'Comm.'
            when salesperson = 'DTC' then 'DTC'
            when lower(salesperson) like '%msr%'
                or lower(salesperson) like '%installer%'
                or lower(salesperson) like '%multi%'
                then 'MSR'
            when lower(salesperson) like '%ind%'
                or lower(salesperson) like '%retail%'
                or lower(salesperson) like '%dealer%'
                then 'Ind. Retail'
            -- Named salespersons in regular store who aren't DTC default
            -- are likely B2B/retail channels
            when store = 'regular' and salesperson != 'DTC' then 'Ind. Retail'
            else 'DTC'
        end as wbr_channel

    from orders
),

-- Aggregate by week and channel
weekly_channel as (
    select
        iso_year,
        iso_week,
        week_start,
        wbr_channel,

        sum(net_sales) as channel_net_sales,
        count(distinct order_id) as channel_orders

    from orders_with_channel
    group by 1, 2, 3, 4
),

-- Get weekly totals for % calculations
weekly_totals as (
    select
        iso_year,
        iso_week,
        week_start,
        sum(net_sales) as total_net_sales,
        count(distinct order_id) as total_orders
    from orders_with_channel
    group by 1, 2, 3
),

final as (
    select
        wc.iso_year,
        wc.iso_week,
        wc.week_start,
        wc.wbr_channel,
        wc.channel_net_sales,
        wc.channel_orders,
        wt.total_net_sales,
        wt.total_orders,

        -- % of total
        safe_divide(wc.channel_net_sales, wt.total_net_sales) as pct_of_total,

        -- Week-over-week change
        lag(wc.channel_net_sales) over (
            partition by wc.wbr_channel
            order by wc.week_start
        ) as prev_week_channel_sales,

        safe_divide(
            wc.channel_net_sales - lag(wc.channel_net_sales) over (
                partition by wc.wbr_channel order by wc.week_start
            ),
            abs(lag(wc.channel_net_sales) over (
                partition by wc.wbr_channel order by wc.week_start
            ))
        ) as wow_change_pct

    from weekly_channel as wc
    inner join weekly_totals as wt
        on wc.iso_year = wt.iso_year
        and wc.iso_week = wt.iso_week
)

select * from final
