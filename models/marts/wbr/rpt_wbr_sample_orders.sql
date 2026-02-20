{{
    config(
        materialized='table'
    )
}}

-- WBR Pages 8-9: Sample Orders + Ordered Sample SKUs
-- Sample Orders = count of orders classified as 'Sample Order'
-- Ordered Sample SKUs = total quantity of sample line items

with

-- Sample order counts from fct_orders
sample_orders_weekly as (
    select
        extract(isoyear from order_date) as iso_year,
        extract(isoweek from order_date) as iso_week,
        date_trunc(order_date, isoweek) as week_start,

        count(distinct order_id) as sample_order_count

    from {{ ref('fct_orders') }}
    where is_sample_order = 1
      and cancel_reason is null
    group by 1, 2, 3
),

-- Sample SKU quantities from int_order_lines_with_product (has cancel flag)
sample_skus_weekly as (
    select
        extract(isoyear from order_date) as iso_year,
        extract(isoweek from order_date) as iso_week,
        date_trunc(order_date, isoweek) as week_start,

        sum(quantity) as sample_sku_count

    from {{ ref('int_order_lines_with_product') }}
    where line_item_type = 'Sample'
      and is_cancelled = 0
    group by 1, 2, 3
),

-- Monthly sample orders
sample_orders_monthly as (
    select
        date_trunc(order_date, month) as month_start,

        count(distinct order_id) as sample_order_count

    from {{ ref('fct_orders') }}
    where is_sample_order = 1
      and cancel_reason is null
    group by 1
),

-- Monthly sample SKUs
sample_skus_monthly as (
    select
        date_trunc(order_date, month) as month_start,

        sum(quantity) as sample_sku_count

    from {{ ref('int_order_lines_with_product') }}
    where line_item_type = 'Sample'
      and is_cancelled = 0
    group by 1
),

-- Weekly combined with w/w and y/y
weekly_combined as (
    select
        coalesce(so.iso_year, ss.iso_year) as iso_year,
        coalesce(so.iso_week, ss.iso_week) as iso_week,
        coalesce(so.week_start, ss.week_start) as week_start,
        coalesce(so.sample_order_count, 0) as sample_order_count,
        coalesce(ss.sample_sku_count, 0) as sample_sku_count

    from sample_orders_weekly as so
    full outer join sample_skus_weekly as ss
        on so.iso_year = ss.iso_year
        and so.iso_week = ss.iso_week
),

weekly_enriched as (
    select
        w.*,

        -- Samples per order ratio
        safe_divide(w.sample_sku_count, w.sample_order_count) as skus_per_order,

        -- w/w for sample orders
        lag(w.sample_order_count) over (order by w.week_start) as prev_week_sample_orders,
        safe_divide(
            w.sample_order_count - lag(w.sample_order_count) over (order by w.week_start),
            abs(lag(w.sample_order_count) over (order by w.week_start))
        ) as sample_orders_wow_pct,

        -- w/w for sample SKUs
        lag(w.sample_sku_count) over (order by w.week_start) as prev_week_sample_skus,
        safe_divide(
            w.sample_sku_count - lag(w.sample_sku_count) over (order by w.week_start),
            abs(lag(w.sample_sku_count) over (order by w.week_start))
        ) as sample_skus_wow_pct,

        -- y/y for sample orders
        yoy.sample_order_count as prior_year_sample_orders,
        safe_divide(
            w.sample_order_count - yoy.sample_order_count,
            abs(yoy.sample_order_count)
        ) as sample_orders_yoy_pct,

        -- y/y for sample SKUs
        yoy.sample_sku_count as prior_year_sample_skus,
        safe_divide(
            w.sample_sku_count - yoy.sample_sku_count,
            abs(yoy.sample_sku_count)
        ) as sample_skus_yoy_pct

    from weekly_combined as w
    left join weekly_combined as yoy
        on w.iso_week = yoy.iso_week
        and w.iso_year = yoy.iso_year + 1
),

-- Combine weekly and monthly
final as (
    -- Weekly
    select
        'weekly' as grain,
        iso_year,
        iso_week,
        week_start as period_start,
        cast(null as date) as month_start,
        sample_order_count,
        sample_sku_count,
        skus_per_order,
        prev_week_sample_orders,
        sample_orders_wow_pct,
        prev_week_sample_skus,
        sample_skus_wow_pct,
        prior_year_sample_orders,
        sample_orders_yoy_pct,
        prior_year_sample_skus,
        sample_skus_yoy_pct
    from weekly_enriched

    union all

    -- Monthly
    select
        'monthly' as grain,
        extract(year from so.month_start) as iso_year,
        cast(null as int64) as iso_week,
        cast(null as date) as period_start,
        so.month_start,
        so.sample_order_count,
        coalesce(ss.sample_sku_count, 0) as sample_sku_count,
        safe_divide(coalesce(ss.sample_sku_count, 0), so.sample_order_count) as skus_per_order,
        cast(null as int64) as prev_week_sample_orders,
        cast(null as float64) as sample_orders_wow_pct,
        cast(null as int64) as prev_week_sample_skus,
        cast(null as float64) as sample_skus_wow_pct,
        cast(null as int64) as prior_year_sample_orders,
        cast(null as float64) as sample_orders_yoy_pct,
        cast(null as int64) as prior_year_sample_skus,
        cast(null as float64) as sample_skus_yoy_pct
    from sample_orders_monthly as so
    left join sample_skus_monthly as ss
        on so.month_start = ss.month_start
)

select * from final
