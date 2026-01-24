{{
    config(
        materialized='view'
    )
}}

/*
    Household Identification via Shipping Address Normalization

    Purpose:
        Creates household_id by normalizing shipping addresses to enable
        conversion tracking when customers use different emails for samples vs products
        but ship to the same physical address.

    Matching Logic:
        - Match Field: Shipping address line 1 + ZIP code
        - Normalization: Lowercase, trim whitespace, remove punctuation

    Grain: order_id (one row per order with household_id assigned)
*/

with orders_with_addresses as (
    select
        order_id,
        email,
        processed_at,
        order_date,
        store,
        shipping_address_line1,
        shipping_address_line2,
        shipping_address_city,
        shipping_state,
        shipping_address_zip,
        shipping_address_country

    from {{ ref('stg_shopify__orders') }}
    where shipping_address_line1 is not null
        and shipping_address_zip is not null
        and email is not null
        and email not like '%amazon%'
),

normalized_addresses as (
    select
        *,
        -- Normalize address: lowercase, remove punctuation, collapse spaces
        trim(
            regexp_replace(
                regexp_replace(
                    lower(shipping_address_line1),
                    '[.,#-]',
                    ''
                ),
                '\\s+',
                ' '
            )
        ) as normalized_address,

        -- Normalize ZIP (take first 5 digits for US)
        case
            when shipping_address_country in ('US', 'United States')
            then left(regexp_replace(shipping_address_zip, '[^0-9]', ''), 5)
            else lower(regexp_replace(shipping_address_zip, '\\s+', ''))
        end as normalized_zip

    from orders_with_addresses
),

final as (
    select
        order_id,
        email,
        processed_at,
        order_date,
        store,
        shipping_address_line1,
        shipping_address_line2,
        shipping_address_city,
        shipping_state,
        shipping_address_zip,
        shipping_address_country,
        normalized_address,
        normalized_zip,

        -- Household key = normalized address + normalized zip
        concat(
            coalesce(normalized_address, ''),
            '|',
            coalesce(normalized_zip, '')
        ) as household_key,

        -- Create stable household_id using FARM_FINGERPRINT (deterministic hash)
        farm_fingerprint(
            concat(
                coalesce(normalized_address, ''),
                '|',
                coalesce(normalized_zip, '')
            )
        ) as household_id

    from normalized_addresses
)

select * from final
