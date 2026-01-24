{{
    config(
        materialized='view'
    )
}}

with

campaign_stats as (
    select
        -- date
        segments_date as date_day,

        -- identifiers
        campaign_id,
        customer_id,

        -- performance metrics
        metrics_clicks as clicks,
        metrics_impressions as impressions,
        metrics_cost_micros / 1000000.0 as spend,  -- convert from micros to dollars
        metrics_conversions as conversions,
        metrics_conversions_value as conversions_value,
        metrics_interactions as interactions,
        metrics_view_through_conversions as view_through_conversions,

        -- segments
        segments_ad_network_type as ad_network_type,
        segments_device as device,

        -- metadata
        _DATA_DATE as data_date,
        _LATEST_DATE as latest_date

    from {{ source('google_ads', 'ads_CampaignBasicStats_8112394732') }}
),

campaigns as (
    select
        campaign_id,
        customer_id,
        campaign_name,
        campaign_advertising_channel_type as channel_type,
        campaign_advertising_channel_sub_type as channel_sub_type,
        campaign_status as status

    from {{ source('google_ads', 'ads_Campaign_8112394732') }}
),

joined as (
    select
        -- date
        stats.date_day,

        -- identifiers
        stats.campaign_id,
        stats.customer_id,
        campaigns.campaign_name,

        -- campaign attributes
        campaigns.channel_type,
        campaigns.channel_sub_type,
        campaigns.status,

        -- performance metrics
        stats.clicks,
        stats.impressions,
        stats.spend,
        stats.conversions,
        stats.conversions_value,
        stats.interactions,
        stats.view_through_conversions,

        -- calculated metrics
        case
            when stats.impressions > 0
            then round(cast(stats.clicks as float64) / stats.impressions * 100, 2)
            else null
        end as ctr,
        case
            when stats.clicks > 0
            then round(stats.spend / stats.clicks, 2)
            else null
        end as cpc,
        case
            when stats.spend > 0
            then round(stats.conversions_value / stats.spend, 2)
            else null
        end as roas,
        case
            when stats.conversions > 0
            then round(stats.spend / stats.conversions, 2)
            else null
        end as cpa,

        -- segments
        stats.ad_network_type,
        stats.device,

        -- channel identifier
        'Google' as channel,

        -- metadata
        stats.data_date,
        stats.latest_date

    from campaign_stats as stats
    left join campaigns
        on stats.campaign_id = campaigns.campaign_id
        and stats.customer_id = campaigns.customer_id
)

select * from joined
