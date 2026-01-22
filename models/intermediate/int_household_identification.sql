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

    Business Case:
        Customer orders sample using work email → home address
        Customer orders product using personal email → same home address
        These orders should count as a conversion at the household level.

    Matching Logic (based on client requirements):
        - Match Field: Shipping address line 1 + ZIP code
        - Normalization: Lowercase, trim whitespace, remove punctuation, standardize abbreviations

    Grain: order_id (one row per order with household_id assigned)

    Usage:
        - Join to int_customer_funnel to track household-level conversions
        - Used in fct_sample_conversions to show both email-based and household-based conversion rates
*/

with orders_with_addresses as (
    select
        order_id,
        email,
        processed_at,
        order_date,
        store,

        -- Raw address fields (shipping only per client requirement)
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
        and email not like '%amazon%'  -- exclude Amazon marketplace
),

normalized_addresses as (
    select
        *,

        -- Step 1: Lowercase
        lower(shipping_address_line1) as normalized_step1,

        -- Step 2: Trim whitespace and collapse multiple spaces
        trim(regexp_replace(lower(shipping_address_line1), r'\s+', ' ')) as normalized_step2,

        -- Step 3: Remove punctuation (periods, commas, hyphens, hashtags)
        regexp_replace(
            trim(regexp_replace(lower(shipping_address_line1), r'\s+', ' ')),
            r'[.,\-#]',
            ''
        ) as normalized_step3,

        -- Step 4: Standardize common abbreviations
        regexp_replace(
            regexp_replace(
                regexp_replace(
                    regexp_replace(
                        regexp_replace(
                            regexp_replace(
                                regexp_replace(
                                    regexp_replace(
                                        regexp_replace(
                                            regexp_replace(
                                                regexp_replace(
                                                    -- Step 3 output
                                                    regexp_replace(
                                                        trim(regexp_replace(lower(shipping_address_line1), r'\s+', ' ')),
                                                        r'[.,\-#]',
                                                        ''
                                                    ),
                                                    r'\bstreet\b', 'st'),  -- Street → st
                                                r'\bavenue\b', 'ave'),         -- Avenue → ave
                                            r'\bdrive\b', 'dr'),               -- Drive → dr
                                            r'\broad\b', 'rd'),                -- Road → rd
                                        r'\blane\b', 'ln'),                    -- Lane → ln
                                    r'\bcourt\b', 'ct'),                       -- Court → ct
                                r'\bcircle\b', 'cir'),                         -- Circle → cir
                            r'\bplace\b', 'pl'),                               -- Place → pl
                        r'\bapartment\b', 'apt'),                              -- Apartment → apt
                    r'\bsuite\b', 'ste'),                                      -- Suite → ste
                r'\bbuilding\b', 'bldg'),                                      -- Building → bldg
            r'\bnorth\b', 'n'                                                  -- North → n
        ) as normalized_address,

        -- Normalize ZIP (remove spaces, hyphens, take first 5 digits for US addresses)
        case
            when shipping_address_country = 'US' or shipping_address_country = 'United States'
            then substr(regexp_replace(shipping_address_zip, r'[^0-9]', ''), 1, 5)
            else lower(regexp_replace(shipping_address_zip, r'\s+', ''))
        end as normalized_zip

    from orders_with_addresses
),

household_keys as (
    select
        *,

        -- Household key = normalized address + normalized zip
        concat(
            coalesce(normalized_address, ''),
            '|',
            coalesce(normalized_zip, '')
        ) as household_key,

        -- Create stable household_id using FARM_FINGERPRINT (deterministic hash)
        -- This creates an integer ID that will be the same for matching addresses
        farm_fingerprint(
            concat(
                coalesce(normalized_address, ''),
                '|',
                coalesce(normalized_zip, '')
            )
        ) as household_id

    from normalized_addresses
),

final as (
    select
        order_id,
        email,
        processed_at,
        order_date,
        store,

        -- Raw address fields (for validation/debugging)
        shipping_address_line1,
        shipping_address_line2,
        shipping_address_city,
        shipping_state,
        shipping_address_zip,
        shipping_address_country,

        -- Normalized fields
        normalized_address,
        normalized_zip,

        -- Household identification
        household_key,
        household_id

    from household_keys
)

select * from final
