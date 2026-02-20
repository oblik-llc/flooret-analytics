{{
    config(
        materialized='table'
    )
}}

-- WBR Page 11: Provence Sampling
-- Daily sample counts for Provenance (Provence) product line
-- Tracks new product launch sampling velocity by SKU and size variant

with

provence_samples as (
    select * from {{ ref('int_order_lines_with_product') }}
    where line_item_type = 'Sample'
      and product_line = 'Provenance'
      and is_cancelled = 0
),

-- Daily by SKU
daily_sku as (
    select
        order_date,
        sku,
        product_line,
        color_code,
        color_name,

        -- Determine size variant from SKU pattern
        -- SA-PE-XXXX-75-CUT = 7.5", SA-PE-XXXX-105-CUT = 10"
        case
            when sku like '%75%' then '7.5"'
            when sku like '%105%' then '10"'
            else 'Unknown'
        end as size_variant,

        count(*) as sample_line_count,
        sum(quantity) as qty_ordered,
        count(distinct order_id) as order_count

    from provence_samples
    group by 1, 2, 3, 4, 5, 6
),

-- Daily totals by size (WBR uses line counts, not quantities)
daily_size_totals as (
    select
        order_date,
        size_variant,
        sum(sample_line_count) as total_lines,
        sum(qty_ordered) as total_qty,
        sum(order_count) as total_orders
    from daily_sku
    group by 1, 2
),

-- Grand daily totals
daily_grand_totals as (
    select
        order_date,
        sum(sample_line_count) as grand_total_lines,
        sum(qty_ordered) as grand_total_qty,
        sum(order_count) as grand_total_orders
    from daily_sku
    group by 1
),

final as (
    select
        ds.order_date,
        ds.sku,
        ds.product_line,
        ds.color_code,
        ds.color_name,
        ds.size_variant,
        ds.sample_line_count,
        ds.qty_ordered,
        ds.order_count,
        dst.total_lines as size_daily_total,
        dgt.grand_total_lines as daily_grand_total,

        -- Running totals (line counts to match WBR)
        sum(ds.sample_line_count) over (partition by ds.sku order by ds.order_date) as sku_cumulative,
        sum(ds.sample_line_count) over (partition by ds.size_variant order by ds.order_date) as size_cumulative

    from daily_sku as ds
    left join daily_size_totals as dst
        on ds.order_date = dst.order_date
        and ds.size_variant = dst.size_variant
    left join daily_grand_totals as dgt
        on ds.order_date = dgt.order_date
)

select * from final
