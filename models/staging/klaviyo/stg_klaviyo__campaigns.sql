{{
    config(
        materialized='view'
    )
}}

with

source as (
    select * from {{ source('ft_klaviyo_klaviyo', 'klaviyo__campaigns') }}
),

renamed as (
    select
        -- Identifiers
        campaign_id,
        campaign_variation_key,
        variation_id,

        -- Campaign metadata
        campaign_name,
        subject,
        campaign_type,
        status,
        from_email,
        from_name,
        email_template_id,
        is_archived,

        -- Timestamps (already in Pacific from Fivetran)
        sent_at,
        scheduled_at,
        created_at,
        updated_at,

        -- Recipients
        total_count_unique_people as recipients,
        unique_count_received_email as received,

        -- Engagement metrics (unique counts for rates)
        unique_count_opened_email as opened,
        unique_count_clicked_email as clicked,
        unique_count_marked_email_as_spam as marked_spam,
        unique_count_unsubscribed as unsubscribed,
        cast(null as int64) as bounced,  -- unique_count_bounced_email not available in source

        -- Total engagement (includes repeats)
        count_opened_email as total_opens,
        count_clicked_email as total_clicks,

        -- Conversion metrics
        unique_count_placed_order as converters,
        count_placed_order as orders,
        sum_revenue_placed_order as revenue,

        -- Additional revenue metrics
        sum_revenue_ordered_product as product_revenue,
        sum_revenue_checkout_started as checkout_started_value,
        sum_revenue_refunded_order as refunded_revenue,
        sum_revenue_cancelled_order as cancelled_revenue,

        -- SMS metrics (if applicable)
        unique_count_received_sms as sms_received,
        unique_count_clicked_sms as sms_clicked

    from source
    where status = 'sent'  -- Only sent campaigns
        and is_archived = false  -- Exclude archived
),

final as (
    select
        *,

        -- Calculated engagement rates
        case when received > 0 then round(cast(opened as float64) / received * 100, 2) else 0 end as open_rate,
        case when received > 0 then round(cast(clicked as float64) / received * 100, 2) else 0 end as click_rate,
        case when opened > 0 then round(cast(clicked as float64) / opened * 100, 2) else 0 end as click_to_open_rate,
        case when received > 0 then round(cast(unsubscribed as float64) / received * 100, 2) else 0 end as unsubscribe_rate,
        case when received > 0 then round(cast(bounced as float64) / received * 100, 2) else 0 end as bounce_rate,

        -- Conversion metrics
        case when received > 0 then round(cast(converters as float64) / received * 100, 2) else 0 end as conversion_rate,
        case when converters > 0 then round(revenue / converters, 2) else 0 end as revenue_per_converter,
        case when received > 0 then round(revenue / received, 2) else 0 end as revenue_per_recipient,
        case when orders > 0 then round(revenue / orders, 2) else 0 end as average_order_value,

        -- Net revenue (after refunds and cancellations)
        revenue - coalesce(refunded_revenue, 0) - coalesce(cancelled_revenue, 0) as net_revenue,

        -- Channel identifier
        'Email' as channel,

        -- Campaign type classification
        case
            when lower(campaign_name) like '%welcome%' then 'Welcome Series'
            when lower(campaign_name) like '%abandon%' or lower(campaign_name) like '%cart%' then 'Cart Abandonment'
            when lower(campaign_name) like '%sample%' then 'Sample Nurture'
            when lower(campaign_name) like '%win%back%' or lower(campaign_name) like '%re%engage%' then 'Winback'
            when lower(campaign_name) like '%promo%' or lower(campaign_name) like '%sale%' then 'Promotion'
            when lower(campaign_name) like '%newsletter%' then 'Newsletter'
            else 'Other'
        end as campaign_category

    from renamed
)

select * from final
