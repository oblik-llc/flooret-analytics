{{
    config(
        materialized='table'
    )
}}

-- WBR Page 10: Top Ordered Sample SKUs
-- Rankings of sample SKUs by quantity ordered (weekly + T6W)

with

sample_lines as (
    select * from {{ ref('int_order_lines_with_product') }}
    where line_item_type = 'Sample'
      and is_cancelled = 0
),

-- Weekly sample SKU counts
weekly_sample_sku as (
    select
        iso_year,
        iso_week,
        iso_week_start as week_start,
        sku,
        product_line,

        sum(quantity) as qty_ordered,
        count(distinct order_id) as order_count

    from sample_lines
    group by 1, 2, 3, 4, 5
),

-- Compute rank first (cannot nest window functions)
weekly_with_rank as (
    select
        *,
        row_number() over (partition by iso_year, iso_week order by qty_ordered desc) as weekly_rank
    from weekly_sample_sku
),

-- Add prev week, deltas, and rolling windows
weekly_ranked as (
    select
        *,

        -- Previous week values
        lag(qty_ordered) over (partition by sku order by week_start) as prev_week_qty,
        lag(weekly_rank) over (partition by sku order by week_start) as prev_week_rank,

        -- Delta
        qty_ordered - lag(qty_ordered) over (partition by sku order by week_start) as wow_delta,

        -- T6W
        sum(qty_ordered) over (
            partition by sku
            order by week_start
            rows between 5 preceding and current row
        ) as t6w_qty,

        -- P6W
        sum(qty_ordered) over (
            partition by sku
            order by week_start
            rows between 11 preceding and 6 preceding
        ) as p6w_qty

    from weekly_with_rank
),

-- T6W rankings
final as (
    select
        *,

        -- T6W delta
        t6w_qty - p6w_qty as t6w_delta,

        -- T6W rank
        row_number() over (
            partition by iso_year, iso_week
            order by t6w_qty desc
        ) as t6w_rank,

        -- P6W rank
        row_number() over (
            partition by iso_year, iso_week
            order by p6w_qty desc
        ) as p6w_rank

    from weekly_ranked
)

select * from final
