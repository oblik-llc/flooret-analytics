{{
    config(
        materialized='view'
    )
}}

with

source as (
    select * from {{ source('ft_facebook_ads_facebook_ads', 'facebook_ads__ad_report') }}
),

renamed as (
    select
        -- date
        date_day,

        -- identifiers
        account_id,
        account_name,
        campaign_id,
        campaign_name,
        ad_set_id,
        ad_set_name,
        ad_id,
        ad_name,

        -- conversion domain
        conversion_domain,

        -- performance metrics
        clicks,
        impressions,
        spend,
        conversions,
        conversions_value,

        -- calculated metrics
        case
            when impressions > 0
            then round(cast(clicks as float64) / impressions * 100, 2)
            else null
        end as ctr,
        case
            when clicks > 0
            then round(spend / clicks, 2)
            else null
        end as cpc,
        case
            when spend > 0
            then round(conversions_value / spend, 2)
            else null
        end as roas,
        case
            when conversions > 0
            then round(spend / conversions, 2)
            else null
        end as cpa,

        -- channel identifier
        'Facebook' as channel,

        -- metadata
        source_relation

    from source
)

select * from renamed
