{{
    config(
        materialized='table',
        partition_by={
            "field": "date_day",
            "data_type": "date",
            "granularity": "day"
        },
        cluster_by=['channel', 'campaign_name']
    )
}}

with

facebook_ads as (
    select
        date_day,
        'Facebook' as channel,
        campaign_id,
        campaign_name,
        ad_set_name,
        ad_name,
        clicks,
        impressions,
        spend,
        conversions,
        conversions_value,
        ctr,
        cpc,
        roas,
        cpa
    from {{ ref('stg_facebook_ads__ad_report') }}
),

google_ads as (
    select
        date_day,
        'Google' as channel,
        campaign_id,
        campaign_name,
        null as ad_set_name,  -- Google doesn't have ad sets like Facebook
        null as ad_name,  -- Campaign-level data only
        clicks,
        impressions,
        spend,
        conversions,
        conversions_value,
        ctr,
        cpc,
        roas,
        cpa
    from {{ ref('stg_google_ads__campaign_stats') }}
),

unioned as (
    select * from facebook_ads
    union all
    select * from google_ads
),

final as (
    select
        -- Date
        date_day,
        extract(year from date_day) as year,
        extract(month from date_day) as month,
        extract(quarter from date_day) as quarter,
        date_trunc(date_day, week) as week_start_date,
        date_trunc(date_day, month) as month_start_date,

        -- Campaign hierarchy
        channel,
        campaign_id,
        campaign_name,
        ad_set_name,
        ad_name,

        -- Performance metrics
        clicks,
        impressions,
        spend,
        conversions,
        conversions_value,

        -- Calculated metrics (already computed in staging, but included here)
        ctr,
        cpc,
        roas,
        cpa,

        -- Additional calculated fields
        case when conversions > 0 then conversions_value / conversions else 0 end as revenue_per_conversion,
        case when clicks > 0 then conversions / clicks else 0 end as click_conversion_rate

    from unioned
)

select * from final
