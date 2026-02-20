{{
    config(
        materialized='view'
    )
}}

with

order_lines as (
    select * from {{ ref('fct_order_lines') }}
),

sku_lookup as (
    select * from {{ ref('seed_sku_lookup') }}
),

orders as (
    select
        order_id,
        store,
        cancel_reason,
        financial_status
    from {{ ref('fct_orders') }}
),

enriched as (
    select
        lines.*,

        -- Order-level status for WBR filtering
        o.cancel_reason,
        o.financial_status,
        case when o.cancel_reason is not null then 1 else 0 end as is_cancelled,

        -- Product hierarchy from seed, with SKU prefix fallback
        coalesce(
            sku_lookup.product_line,
            case
                when lines.sku like 'FL-MR-%' or lines.sku like 'SA-MR-%' then 'Modin'
                when lines.sku like 'FL-SR-%' or lines.sku like 'SA-SR-%' then 'Silvan'
                when lines.sku like 'FL-AR-%' or lines.sku like 'SA-AR-%' then 'Arista'
                when lines.sku like 'FL-PE-%' or lines.sku like 'SA-PE-%' then 'Provenance'
                when lines.sku like 'AC-%' then 'Accessories'
                else 'Other'
            end
        ) as product_line,
        sku_lookup.product_category,
        sku_lookup.bevel,
        sku_lookup.color_code,
        sku_lookup.color_name,

        -- WBR product sub-line (for Page 4 breakdowns)
        case
            -- Modin sub-lines
            when sku_lookup.product_line = 'Modin' and sku_lookup.product_category = 'Signature' and sku_lookup.bevel = 'Enhanced'
                then 'Signature Enhanced'
            when sku_lookup.product_line = 'Modin' and sku_lookup.product_category = 'Signature' and sku_lookup.bevel = 'Micro'
                then 'Signature Micro'
            when sku_lookup.product_line = 'Modin' and sku_lookup.product_category = 'Base'
                then 'Base'
            when sku_lookup.product_line = 'Modin' and sku_lookup.product_category = 'Craftsman'
                then 'Craftsman'
            when sku_lookup.product_line = 'Modin' and sku_lookup.product_category = 'Herringbone'
                then 'Herringbone'
            -- Silvan sub-lines (product_category contains width)
            when sku_lookup.product_line = 'Silvan' and sku_lookup.product_category like '7%'
                then '7"'
            when sku_lookup.product_line = 'Silvan' and sku_lookup.product_category like '6%'
                then '6"'
            when sku_lookup.product_line = 'Silvan' and sku_lookup.product_category = 'Base'
                then '6"'
            -- Arista / Provenance have no sub-lines in WBR
            else sku_lookup.product_category
        end as wbr_product_subline,

        -- ISO week dimensions for WBR
        extract(isoyear from lines.order_date) as iso_year,
        extract(isoweek from lines.order_date) as iso_week,
        date_trunc(lines.order_date, isoweek) as iso_week_start

    from order_lines as lines
    left join sku_lookup
        on lines.sku = sku_lookup.sku
    left join orders as o
        on lines.order_id = o.order_id
        and lines.store = o.store
)

select * from enriched
