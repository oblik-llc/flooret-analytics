{{
    config(
        materialized='table'
    )
}}

-- WBR Page 4: Product Line Performance
-- Revenue by product_line (Modin/Silvan/Arista) and sub-line
-- Uses line-item level revenue (line_total = price * quantity)
-- Includes Product type line items only (FL- SKUs)

with

order_lines as (
    select * from {{ ref('int_order_lines_with_product') }}
    where line_item_type = 'Product'
      and is_cancelled = 0
      and store = 'regular'
),

-- Weekly by product line (top level: Modin, Silvan, Arista)
weekly_product_line as (
    select
        iso_year,
        iso_week,
        iso_week_start as week_start,
        product_line,

        sum(line_total) as revenue,
        count(distinct order_id) as order_count,
        sum(quantity) as units_sold

    from order_lines
    where product_line is not null
    group by 1, 2, 3, 4
),

-- Weekly by product sub-line (Signature Enhanced, Base, etc.)
weekly_subline as (
    select
        iso_year,
        iso_week,
        iso_week_start as week_start,
        product_line,
        wbr_product_subline,

        sum(line_total) as revenue,
        count(distinct order_id) as order_count,
        sum(quantity) as units_sold

    from order_lines
    where product_line is not null
    group by 1, 2, 3, 4, 5
),

-- Get weekly totals for % of total
weekly_totals as (
    select
        iso_year,
        iso_week,
        week_start,
        sum(revenue) as total_revenue
    from weekly_product_line
    group by 1, 2, 3
),

-- Product line with w/w and % of total
product_line_enriched as (
    select
        'product_line' as grain,
        pl.iso_year,
        pl.iso_week,
        pl.week_start,
        pl.product_line,
        cast(null as string) as wbr_product_subline,
        pl.revenue,
        pl.order_count,
        pl.units_sold,
        wt.total_revenue,

        -- % of total
        safe_divide(pl.revenue, wt.total_revenue) as pct_of_total,

        -- w/w change
        lag(pl.revenue) over (partition by pl.product_line order by pl.week_start) as prev_week_revenue,
        pl.revenue - lag(pl.revenue) over (partition by pl.product_line order by pl.week_start) as wow_change_dollars,
        safe_divide(
            pl.revenue - lag(pl.revenue) over (partition by pl.product_line order by pl.week_start),
            abs(lag(pl.revenue) over (partition by pl.product_line order by pl.week_start))
        ) as wow_change_pct,

        -- T6W (trailing 6 weeks including current)
        sum(pl.revenue) over (
            partition by pl.product_line
            order by pl.week_start
            rows between 5 preceding and current row
        ) as t6w_revenue

    from weekly_product_line as pl
    inner join weekly_totals as wt
        on pl.iso_year = wt.iso_year
        and pl.iso_week = wt.iso_week
),

-- Sub-line with w/w and % of total (within product line)
subline_with_parent_totals as (
    select
        sl.iso_year,
        sl.iso_week,
        sl.week_start,
        sl.product_line,
        sl.wbr_product_subline,
        sl.revenue,
        sl.order_count,
        sl.units_sold,
        pl.revenue as product_line_revenue
    from weekly_subline as sl
    inner join weekly_product_line as pl
        on sl.iso_year = pl.iso_year
        and sl.iso_week = pl.iso_week
        and sl.product_line = pl.product_line
),

subline_enriched as (
    select
        'subline' as grain,
        iso_year,
        iso_week,
        week_start,
        product_line,
        wbr_product_subline,
        revenue,
        order_count,
        units_sold,
        product_line_revenue as total_revenue,

        -- % of product line total
        safe_divide(revenue, product_line_revenue) as pct_of_total,

        -- w/w change
        lag(revenue) over (partition by product_line, wbr_product_subline order by week_start) as prev_week_revenue,
        revenue - lag(revenue) over (partition by product_line, wbr_product_subline order by week_start) as wow_change_dollars,
        safe_divide(
            revenue - lag(revenue) over (partition by product_line, wbr_product_subline order by week_start),
            abs(lag(revenue) over (partition by product_line, wbr_product_subline order by week_start))
        ) as wow_change_pct,

        -- T6W
        sum(revenue) over (
            partition by product_line, wbr_product_subline
            order by week_start
            rows between 5 preceding and current row
        ) as t6w_revenue

    from subline_with_parent_totals
),

-- Union product line and sub-line rows
final as (
    select * from product_line_enriched
    union all
    select * from subline_enriched
)

select * from final
