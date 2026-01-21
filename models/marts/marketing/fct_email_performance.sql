{{
    config(
        materialized='table',
        cluster_by=['channel', 'campaign_type']
    )
}}

with

campaigns as (
    select
        campaign_id as email_id,
        'Campaign' as email_type,
        campaign_name as email_name,
        campaign_category as email_category,
        sent_at as sent_at,
        date(sent_at) as sent_date,
        subject,
        from_email,
        from_name,
        recipients,
        received,
        opened,
        clicked,
        converters,
        orders,
        revenue,
        net_revenue,
        open_rate,
        click_rate,
        click_to_open_rate,
        conversion_rate,
        revenue_per_converter,
        revenue_per_recipient,
        average_order_value,
        unsubscribed,
        unsubscribe_rate,
        bounced,
        bounce_rate,
        marked_spam,
        channel
    from {{ ref('stg_klaviyo__campaigns') }}
),

flows as (
    select
        flow_id as email_id,
        'Flow' as email_type,
        flow_name as email_name,
        flow_category as email_category,
        null as sent_at,  -- Flows don't have a single send date
        null as sent_date,
        null as subject,  -- Flows have multiple messages with different subjects
        null as from_email,
        null as from_name,
        recipients,
        received,
        opened,
        clicked,
        converters,
        orders,
        revenue,
        net_revenue,
        open_rate,
        click_rate,
        click_to_open_rate,
        conversion_rate,
        revenue_per_converter,
        revenue_per_recipient,
        average_order_value,
        unsubscribed,
        unsubscribe_rate,
        bounced,
        bounce_rate,
        marked_spam,
        channel
    from {{ ref('stg_klaviyo__flows') }}
),

unioned as (
    select * from campaigns
    union all
    select * from flows
),

final as (
    select
        -- Identifiers
        email_id,
        email_type,
        email_name,
        email_category,

        -- Send metadata (campaigns only)
        sent_at,
        sent_date,
        case when sent_date is not null then extract(year from sent_date) end as sent_year,
        case when sent_date is not null then extract(month from sent_date) end as sent_month,
        case when sent_date is not null then extract(quarter from sent_date) end as sent_quarter,
        case when sent_date is not null then date_trunc(sent_date, week) end as sent_week_start_date,
        case when sent_date is not null then date_trunc(sent_date, month) end as sent_month_start_date,

        subject,
        from_email,
        from_name,

        -- Recipient metrics
        recipients,
        received,

        -- Engagement metrics
        opened,
        clicked,
        open_rate,
        click_rate,
        click_to_open_rate,

        -- Conversion metrics
        converters,
        orders,
        revenue,
        net_revenue,
        conversion_rate,
        revenue_per_converter,
        revenue_per_recipient,
        average_order_value,

        -- Negative engagement
        unsubscribed,
        unsubscribe_rate,
        bounced,
        bounce_rate,
        marked_spam,

        -- Channel
        channel

    from unioned
)

select * from final
