{{
    config(
        materialized='view'
    )
}}

with

regular_shopify as (
    select
        -- identifiers
        order_id,
        customer_id,
        user_id,

        -- customer info
        lower(email) as email,

        -- timestamps (convert to Pacific timezone)
        datetime(processed_timestamp, 'America/Los_Angeles') as processed_at,
        datetime(created_timestamp, 'America/Los_Angeles') as created_at,
        datetime(cancelled_timestamp, 'America/Los_Angeles') as cancelled_at,
        datetime(closed_timestamp, 'America/Los_Angeles') as closed_at,
        datetime(updated_timestamp, 'America/Los_Angeles') as updated_at,

        -- monetary fields (use presentation currency amounts)
        subtotal_price_pres_amount as subtotal_price,
        total_price_pres_amount as total_price,
        total_discounts_pres_amount as total_discounts,
        total_tax_pres_amount as total_tax,
        total_tip_received_pres_amount as total_tip_received,

        -- order metadata
        name as order_name,
        number as order_number,
        note,
        source_name,

        -- status fields
        financial_status,
        fulfillment_status,
        cancel_reason,

        -- location
        location_id,
        billing_address_address_1 as billing_address_line1,
        billing_address_address_2 as billing_address_line2,
        billing_address_city,
        billing_address_province as billing_state,
        billing_address_province_code as billing_state_code,
        billing_address_zip,
        billing_address_country,
        billing_address_country_code,
        shipping_address_address_1 as shipping_address_line1,
        shipping_address_address_2 as shipping_address_line2,
        shipping_address_city,
        shipping_address_province as shipping_state,
        shipping_address_province_code as shipping_state_code,
        shipping_address_zip,
        shipping_address_country,
        shipping_address_country_code,

        -- tags for salesperson extraction
        tags,

        -- store identifier
        'regular' as store,
        55 as product_price_threshold,
        'DTC' as default_salesperson,

        -- fivetran metadata
        _fivetran_synced,
        source_relation

    from {{ source('ft_shopify_shopify', 'int_shopify_gql__order') }}
    where source_relation like '%shopify.shopify%'
),

commercial_shopify as (
    select
        -- identifiers
        order_id,
        customer_id,
        user_id,

        -- customer info
        lower(email) as email,

        -- timestamps (convert to Pacific timezone)
        datetime(processed_timestamp, 'America/Los_Angeles') as processed_at,
        datetime(created_timestamp, 'America/Los_Angeles') as created_at,
        datetime(cancelled_timestamp, 'America/Los_Angeles') as cancelled_at,
        datetime(closed_timestamp, 'America/Los_Angeles') as closed_at,
        datetime(updated_timestamp, 'America/Los_Angeles') as updated_at,

        -- monetary fields (use presentation currency amounts)
        subtotal_price_pres_amount as subtotal_price,
        total_price_pres_amount as total_price,
        total_discounts_pres_amount as total_discounts,
        total_tax_pres_amount as total_tax,
        total_tip_received_pres_amount as total_tip_received,

        -- order metadata
        name as order_name,
        number as order_number,
        note,
        source_name,

        -- status fields
        financial_status,
        fulfillment_status,
        cancel_reason,

        -- location
        location_id,
        billing_address_address_1 as billing_address_line1,
        billing_address_address_2 as billing_address_line2,
        billing_address_city,
        billing_address_province as billing_state,
        billing_address_province_code as billing_state_code,
        billing_address_zip,
        billing_address_country,
        billing_address_country_code,
        shipping_address_address_1 as shipping_address_line1,
        shipping_address_address_2 as shipping_address_line2,
        shipping_address_city,
        shipping_address_province as shipping_state,
        shipping_address_province_code as shipping_state_code,
        shipping_address_zip,
        shipping_address_country,
        shipping_address_country_code,

        -- tags for salesperson extraction
        tags,

        -- store identifier
        'commercial' as store,
        40 as product_price_threshold,
        'Commercial' as default_salesperson,

        -- fivetran metadata
        _fivetran_synced,
        source_relation

    from {{ source('ft_shopify_commercial_shopify', 'int_shopify_gql__order') }}
    where source_relation like '%shopify_commercial%'
),

unioned as (
    select * from regular_shopify
    union all
    select * from commercial_shopify
),

final as (
    select
        *,
        -- extract salesperson from tags, default to store's default
        coalesce(
            regexp_extract(tags, r'Salesperson: (.*?),'),
            default_salesperson
        ) as salesperson,

        -- date fields for easy filtering
        date(processed_at) as order_date,
        extract(year from processed_at) as order_year,
        extract(month from processed_at) as order_month,
        extract(quarter from processed_at) as order_quarter

    from unioned
)

select * from final
