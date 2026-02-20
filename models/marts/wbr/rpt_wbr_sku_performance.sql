{{
    config(
        materialized='table'
    )
}}

-- WBR Pages 5-7: Top Selling SKUs, Top Movers, Top 25 Performance
-- SKU-level net $ = SUM(line_total) for Product line items
-- Includes weekly, T6W, P6W, rankings, deltas, DTC benchmark

with

order_lines as (
    select * from {{ ref('int_order_lines_with_product') }}
    where line_item_type = 'Product'
      and is_cancelled = 0
      and store = 'regular'
),

-- Weekly SKU performance
weekly_sku as (
    select
        iso_year,
        iso_week,
        iso_week_start as week_start,
        sku,
        product_line,
        wbr_product_subline,

        sum(line_total) as net_dollars,
        count(distinct order_id) as order_count,
        sum(quantity) as units_sold

    from order_lines
    group by 1, 2, 3, 4, 5, 6
),

-- Add weekly rank first (cannot nest window functions)
weekly_ranked as (
    select
        *,
        row_number() over (partition by iso_year, iso_week order by net_dollars desc) as weekly_rank
    from weekly_sku
),

-- Add previous week for delta calculations
weekly_with_prev as (
    select
        *,

        -- Previous week values
        lag(net_dollars) over (partition by sku order by week_start) as prev_week_net_dollars,
        lag(order_count) over (partition by sku order by week_start) as prev_week_orders,

        -- Weekly delta
        net_dollars - lag(net_dollars) over (partition by sku order by week_start) as wow_delta_dollars,

        -- Weekly % change (handle zero/null prev week)
        case
            when lag(net_dollars) over (partition by sku order by week_start) is null then null
            when lag(net_dollars) over (partition by sku order by week_start) = 0 then null  -- infinity
            else safe_divide(
                net_dollars - lag(net_dollars) over (partition by sku order by week_start),
                abs(lag(net_dollars) over (partition by sku order by week_start))
            )
        end as wow_change_pct,

        -- Previous week rank (lag on pre-computed rank)
        lag(weekly_rank) over (partition by sku order by week_start) as prev_week_rank

    from weekly_ranked
),

-- T6W and P6W rolling calculations
rolling as (
    select
        *,

        -- T6W (trailing 6 weeks including current)
        sum(net_dollars) over (
            partition by sku
            order by week_start
            rows between 5 preceding and current row
        ) as t6w_net_dollars,

        sum(order_count) over (
            partition by sku
            order by week_start
            rows between 5 preceding and current row
        ) as t6w_orders,

        -- P6W (prior 6 weeks = rows 11 to 6 preceding)
        sum(net_dollars) over (
            partition by sku
            order by week_start
            rows between 11 preceding and 6 preceding
        ) as p6w_net_dollars,

        sum(order_count) over (
            partition by sku
            order by week_start
            rows between 11 preceding and 6 preceding
        ) as p6w_orders,

        -- Count of weeks in window (for validation)
        count(*) over (
            partition by sku
            order by week_start
            rows between 5 preceding and current row
        ) as t6w_week_count

    from weekly_with_prev
),

-- T6W rankings and deltas
t6w_enriched as (
    select
        *,

        -- T6W delta
        t6w_net_dollars - p6w_net_dollars as t6w_delta_dollars,
        safe_divide(
            t6w_net_dollars - p6w_net_dollars,
            nullif(abs(p6w_net_dollars), 0)
        ) as t6w_change_pct,

        -- T6W rank
        row_number() over (
            partition by iso_year, iso_week
            order by t6w_net_dollars desc
        ) as t6w_rank,

        -- P6W rank (for comparison)
        row_number() over (
            partition by iso_year, iso_week
            order by p6w_net_dollars desc
        ) as p6w_rank

    from rolling
),

-- DTC benchmark: overall T6W % change across all SKUs
dtc_benchmark as (
    select
        iso_year,
        iso_week,
        safe_divide(
            sum(t6w_net_dollars) - sum(p6w_net_dollars),
            nullif(abs(sum(p6w_net_dollars)), 0)
        ) as dtc_benchmark_pct
    from t6w_enriched
    group by 1, 2
),

final as (
    select
        t.*,
        dtc.dtc_benchmark_pct,

        -- Delta vs DTC benchmark (SKU's T6W % - DTC benchmark %)
        t.t6w_change_pct - dtc.dtc_benchmark_pct as delta_vs_dtc_pct

    from t6w_enriched as t
    left join dtc_benchmark as dtc
        on t.iso_year = dtc.iso_year
        and t.iso_week = dtc.iso_week
)

select * from final
