{{
    config(
        materialized='view'
    )
}}

with

regular_shopify as (
    select
        -- identifiers
        customer_id,
        lower(email) as email,

        -- customer info
        first_name,
        last_name,
        phone,
        note,

        -- customer attributes
        account_state,
        is_tax_exempt,
        is_verified_email,
        currency,

        -- marketing consent
        marketing_consent_state,
        marketing_opt_in_level,
        marketing_consent_updated_at,

        -- timestamps
        datetime(created_timestamp, 'America/Los_Angeles') as created_at,
        datetime(updated_timestamp, 'America/Los_Angeles') as updated_at,
        datetime(first_order_timestamp, 'America/Los_Angeles') as first_order_at,
        datetime(most_recent_order_timestamp, 'America/Los_Angeles') as most_recent_order_at,

        -- tags for customer group/type extraction
        customer_tags as tags,

        -- lifetime metrics from Shopify
        lifetime_count_orders,
        lifetime_total_spent,
        lifetime_total_refunded,
        lifetime_total_net,
        lifetime_total_tax,
        lifetime_total_discount,
        lifetime_abandoned_checkouts,
        avg_order_value,
        avg_quantity_per_order,
        avg_tax_per_order,

        -- store identifier
        'regular' as store,

        -- fivetran metadata
        _fivetran_synced,
        source_relation

    from {{ source('ft_shopify_shopify', 'shopify_gql__customers') }}
    where source_relation like '%shopify.shopify%'
),

commercial_shopify as (
    select
        -- identifiers
        customer_id,
        lower(email) as email,

        -- customer info
        first_name,
        last_name,
        phone,
        note,

        -- customer attributes
        account_state,
        is_tax_exempt,
        is_verified_email,
        currency,

        -- marketing consent
        marketing_consent_state,
        marketing_opt_in_level,
        marketing_consent_updated_at,

        -- timestamps
        datetime(created_timestamp, 'America/Los_Angeles') as created_at,
        datetime(updated_timestamp, 'America/Los_Angeles') as updated_at,
        datetime(first_order_timestamp, 'America/Los_Angeles') as first_order_at,
        datetime(most_recent_order_timestamp, 'America/Los_Angeles') as most_recent_order_at,

        -- tags for customer group/type extraction
        customer_tags as tags,

        -- lifetime metrics from Shopify
        lifetime_count_orders,
        lifetime_total_spent,
        lifetime_total_refunded,
        lifetime_total_net,
        lifetime_total_tax,
        lifetime_total_discount,
        lifetime_abandoned_checkouts,
        avg_order_value,
        avg_quantity_per_order,
        avg_tax_per_order,

        -- store identifier
        'commercial' as store,

        -- fivetran metadata
        _fivetran_synced,
        source_relation

    from {{ source('ft_shopify_commercial_shopify', 'shopify_gql__customers') }}
    where source_relation like '%shopify_commercial%'
),

unioned as (
    select * from regular_shopify
    union all
    select * from commercial_shopify
),

-- Deduplicate by email (primary customer identifier)
-- Take the most recently updated record per email
deduped as (
    select * from (
        select
            *,
            row_number() over (
                partition by email
                order by updated_at desc, _fivetran_synced desc
            ) as row_num
        from unioned
        where email is not null  -- exclude records without email
    )
    where row_num = 1
),

final as (
    select
        -- remove row_num helper column
        * except(row_num),

        -- Customer Group derivation (business_rules.md section 4)
        case
            when lower(tags) like '%pending%' then 'Pending Trade Rewards'
            when (
                lower(tags) like '%trade%'
                or lower(tags) like '%legacy tr%'
                or lower(tags) like '%partner plus%'
            ) then 'Trade Rewards'
            when (
                lower(tags) like '%retail%'
                or lower(tags) like '%guest%'
                or tags is null
                or tags = ''
            ) then 'Retail'
            else 'Retail'  -- default
        end as customer_group,

        -- Customer Type extraction (business_rules.md section 5)
        coalesce(
            regexp_extract(tags, r'Customer Type: (.*?),'),
            'DTC'
        ) as customer_type

    from deduped
)

select * from final
