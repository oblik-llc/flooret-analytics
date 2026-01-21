{{
    config(
        materialized='view'
    )
}}

with

regular_shopify as (
    select
        -- identifiers
        order_line_id,
        order_id,
        product_id,
        variant_id,

        -- line item details
        sku,
        title,
        name as line_item_name,
        quantity,
        price_pres_amount as price,
        total_discount_pres_amount as total_discount,

        -- metadata
        vendor,
        variant_title,
        is_gift_card,
        is_taxable,
        is_shipping_required,
        fulfillment_status,
        index as line_item_index,

        -- store identifier for price threshold logic
        'regular' as store,
        55 as product_price_threshold,

        -- fivetran metadata
        _fivetran_synced,
        source_relation

    from {{ source('ft_shopify_shopify', 'shopify_gql__order_lines') }}
    where source_relation like '%shopify.shopify%'
),

commercial_shopify as (
    select
        -- identifiers
        order_line_id,
        order_id,
        product_id,
        variant_id,

        -- line item details
        sku,
        title,
        name as line_item_name,
        quantity,
        price_pres_amount as price,
        total_discount_pres_amount as total_discount,

        -- metadata
        vendor,
        variant_title,
        is_gift_card,
        is_taxable,
        is_shipping_required,
        fulfillment_status,
        index as line_item_index,

        -- store identifier for price threshold logic
        'commercial' as store,
        40 as product_price_threshold,

        -- fivetran metadata
        _fivetran_synced,
        source_relation

    from {{ source('ft_shopify_commercial_shopify', 'shopify_gql__order_lines') }}
    where source_relation like '%shopify_commercial%'
),

unioned as (
    select * from regular_shopify
    union all
    select * from commercial_shopify
),

classified as (
    select
        *,

        -- Line Item Classification Logic (business_rules.md section 1)
        -- SKU prefix patterns are primary indicators (SA-, KIT, FL-, AC-)
        -- Title/SKU substrings and price are fallback methods for legacy data
        case
            -- Sample: Primary indicators (SKU prefix)
            when sku like 'SA-%' then 'Sample'
            when sku like 'KIT%' then 'Sample'
            -- Sample: Fallback indicators (title/SKU substrings)
            when lower(title) like '%cut%' then 'Sample'
            when lower(title) like '%sample%' then 'Sample'
            when lower(title) like '%plank%' then 'Sample'
            when lower(sku) like '%cut%' then 'Sample'
            when lower(sku) like '%full%' then 'Sample'

            -- Product: Primary indicator (SKU prefix)
            when sku like 'FL-%' then 'Product'
            -- Product: Fallback indicator (price threshold, excluding Nosing)
            when price > product_price_threshold
                and lower(title) not like '%nosing%' then 'Product'

            -- Accessories: Primary indicator (SKU prefix) or default
            when sku like 'AC-%' then 'Accessories'
            else 'Accessories'
        end as line_item_type,

        -- Sample Type Classification (business_rules.md section 2)
        case
            when lower(title) like '%cut%'
                or lower(sku) like '%cut%'
                or lower(title) like '%sample%' then 'Sample - Cut'
            when lower(title) like '%plank%'
                or lower(sku) like '%full%' then 'Sample - Plank'
            else null
        end as sample_type,

        -- Color Extraction (business_rules.md section 10)
        coalesce(
            regexp_extract(title, r'^(.+?)\s'),
            title
        ) as color,

        -- Calculate line total
        price * quantity as line_total

    from unioned
),

final as (
    select
        *,

        -- Quantity breakdowns for aggregation (business_rules.md section 16)
        case when line_item_type = 'Sample' then quantity else 0 end as sample_quantity,
        case when line_item_type = 'Product' then quantity else 0 end as product_quantity,
        case when line_item_type = 'Accessories' then quantity else 0 end as accessories_quantity,

        -- Revenue breakdowns (business_rules.md section 17)
        case when line_item_type = 'Sample' then line_total else 0 end as sample_revenue,
        case when line_item_type = 'Product' then line_total else 0 end as product_revenue,
        case when line_item_type = 'Accessories' then line_total else 0 end as accessories_revenue

    from classified
)

select * from final
