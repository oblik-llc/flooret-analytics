{{
    config(
        materialized='view'
    )
}}

with

source as (
    select * from {{ source('analytics_266190494', 'events_*') }}
    -- Limit to recent data for performance (adjust as needed)
    where _table_suffix >= format_date('%Y%m%d', date_sub(current_date(), interval 90 day))
),

renamed as (
    select
        -- Event identifiers
        event_date,
        event_name,
        event_bundle_sequence_id,

        -- Timestamps (convert from microseconds to Pacific timezone)
        timestamp_micros(event_timestamp) as event_timestamp_utc,
        datetime(timestamp_micros(event_timestamp), 'America/Los_Angeles') as event_timestamp_pt,
        date(datetime(timestamp_micros(event_timestamp), 'America/Los_Angeles')) as event_date_pt,

        timestamp_micros(event_previous_timestamp) as event_previous_timestamp_utc,
        datetime(timestamp_micros(event_previous_timestamp), 'America/Los_Angeles') as event_previous_timestamp_pt,

        -- Event value
        event_value_in_usd,

        -- User identifiers
        user_id,
        user_pseudo_id,

        -- User timestamps
        timestamp_micros(user_first_touch_timestamp) as user_first_touch_timestamp_utc,

        -- Device
        device.category as device_category,
        device.mobile_brand_name as device_brand,
        device.mobile_model_name as device_model,
        device.operating_system as operating_system,
        device.operating_system_version as os_version,
        device.web_info.browser as browser,
        device.web_info.browser_version as browser_version,
        device.language as device_language,

        -- Geography
        geo.continent as geo_continent,
        geo.country as geo_country,
        geo.region as geo_region,
        geo.city as geo_city,
        geo.metro as geo_metro,

        -- Traffic source
        traffic_source.name as traffic_source_name,
        traffic_source.medium as traffic_source_medium,
        traffic_source.source as traffic_source_source,

        -- App info (for mobile apps, usually null for web)
        app_info.id as app_id,
        app_info.version as app_version,

        -- Platform (web or mobile)
        platform,

        -- Privacy info
        privacy_info.analytics_storage as analytics_storage_consent,
        privacy_info.ads_storage as ads_storage_consent,

        -- E-commerce (nested struct)
        ecommerce,

        -- Event params (keep raw for extraction)
        event_params,

        -- User properties (keep raw for extraction)
        user_properties

    from source
),

-- Extract key event parameters from the nested array
params_extracted as (
    select
        *,

        -- Page tracking
        (select value.string_value from unnest(event_params) where key = 'page_location') as page_location,
        (select value.string_value from unnest(event_params) where key = 'page_referrer') as page_referrer,
        (select value.string_value from unnest(event_params) where key = 'page_title') as page_title,

        -- Session tracking
        (select value.int_value from unnest(event_params) where key = 'ga_session_id') as ga_session_id,
        (select value.int_value from unnest(event_params) where key = 'ga_session_number') as ga_session_number,
        (select value.int_value from unnest(event_params) where key = 'engagement_time_msec') as engagement_time_msec,

        -- E-commerce parameters
        (select value.string_value from unnest(event_params) where key = 'transaction_id') as transaction_id,
        (select value.double_value from unnest(event_params) where key = 'value') as transaction_value,
        (select value.string_value from unnest(event_params) where key = 'currency') as currency,
        (select value.double_value from unnest(event_params) where key = 'tax') as tax,
        (select value.double_value from unnest(event_params) where key = 'shipping') as shipping,
        (select value.string_value from unnest(event_params) where key = 'coupon') as coupon,

        -- Product parameters (for view_item, add_to_cart events)
        (select value.string_value from unnest(event_params) where key = 'item_id') as item_id,
        (select value.string_value from unnest(event_params) where key = 'item_name') as item_name,
        (select value.string_value from unnest(event_params) where key = 'item_category') as item_category,
        (select value.string_value from unnest(event_params) where key = 'item_variant') as item_variant,
        (select value.double_value from unnest(event_params) where key = 'price') as item_price,
        (select value.int_value from unnest(event_params) where key = 'quantity') as item_quantity,

        -- Campaign tracking (UTM parameters)
        (select value.string_value from unnest(event_params) where key = 'campaign') as utm_campaign,
        (select value.string_value from unnest(event_params) where key = 'source') as utm_source,
        (select value.string_value from unnest(event_params) where key = 'medium') as utm_medium,
        (select value.string_value from unnest(event_params) where key = 'term') as utm_term,
        (select value.string_value from unnest(event_params) where key = 'content') as utm_content,

        -- Search tracking
        (select value.string_value from unnest(event_params) where key = 'search_term') as search_term

    from renamed
),

final as (
    select
        *,

        -- Event categorization flags for easier filtering
        case when event_name = 'purchase' then 1 else 0 end as is_purchase,
        case when event_name = 'add_to_cart' then 1 else 0 end as is_add_to_cart,
        case when event_name = 'remove_from_cart' then 1 else 0 end as is_remove_from_cart,
        case when event_name = 'view_item' then 1 else 0 end as is_view_item,
        case when event_name = 'view_item_list' then 1 else 0 end as is_view_item_list,
        case when event_name = 'select_item' then 1 else 0 end as is_select_item,
        case when event_name = 'begin_checkout' then 1 else 0 end as is_begin_checkout,
        case when event_name = 'add_payment_info' then 1 else 0 end as is_add_payment_info,
        case when event_name = 'add_shipping_info' then 1 else 0 end as is_add_shipping_info,
        case when event_name = 'page_view' then 1 else 0 end as is_page_view,
        case when event_name = 'session_start' then 1 else 0 end as is_session_start,
        case when event_name = 'first_visit' then 1 else 0 end as is_first_visit,

        -- Engagement time in seconds
        case when engagement_time_msec is not null then engagement_time_msec / 1000.0 else null end as engagement_time_seconds,

        -- Time between events (in seconds)
        case
            when event_previous_timestamp_pt is not null
            then datetime_diff(event_timestamp_pt, event_previous_timestamp_pt, second)
            else null
        end as seconds_since_previous_event,

        -- Extract page type from URL (basic classification)
        case
            when page_location like '%/products/%' then 'product_detail'
            when page_location like '%/collections/%' then 'product_list'
            when page_location like '%/cart%' then 'cart'
            when page_location like '%/checkout%' then 'checkout'
            when page_location like '%/pages/samples%' or page_location like '%/sample%' then 'samples'
            when page_location = '/' or page_location like '%flooret.com/' then 'homepage'
            else 'other'
        end as page_type

    from params_extracted
)

select * from final
