{{
    config(
        materialized='table',
        partition_by={"field": "session_date", "data_type": "date", "granularity": "day"},
        cluster_by=['deepest_funnel_stage']
    )
}}

/*
    GA4 Website Funnel Fact Table

    Purpose:
        Daily aggregated funnel metrics showing conversion and dropoff rates at each stage.
        Enables funnel visualization and optimization analysis in Sigma dashboards.

    Grain: session_date + deepest_funnel_stage (daily aggregated by final stage reached)

    Key Metrics:
        - Session counts by funnel stage
        - Conversion rates from stage to stage
        - Overall conversion rate (sessions → purchases)
        - Dropoff rates at each stage
        - Average transaction value for converted sessions

    Usage:
        - Funnel visualization dashboards
        - Conversion optimization analysis
        - A/B test impact measurement
        - Time-series funnel performance tracking
*/

with daily_sessions as (
    select
        session_date,
        deepest_funnel_stage,
        funnel_stage_depth,

        -- Session counts
        count(*) as total_sessions,
        count(distinct user_pseudo_id) as unique_users,

        -- Funnel stage reach counts
        sum(reached_homepage) as sessions_reached_homepage,
        sum(reached_plp) as sessions_reached_plp,
        sum(reached_pdp) as sessions_reached_pdp,
        sum(reached_add_to_cart) as sessions_reached_cart,
        sum(reached_begin_checkout) as sessions_reached_checkout,
        sum(reached_purchase) as sessions_reached_purchase,

        -- Dropoff counts
        sum(dropped_at_homepage) as sessions_dropped_at_homepage,
        sum(dropped_at_plp) as sessions_dropped_at_plp,
        sum(dropped_at_pdp) as sessions_dropped_at_pdp,
        sum(dropped_at_cart) as sessions_dropped_at_cart,
        sum(dropped_at_checkout) as sessions_dropped_at_checkout,

        -- Purchase metrics
        sum(is_converted_session) as converted_sessions,
        sum(transaction_value) as total_transaction_value,

        -- Engagement metrics
        avg(session_duration_minutes) as avg_session_duration_minutes,
        avg(total_events) as avg_events_per_session,
        avg(pdp_views) as avg_pdp_views_per_session

    from {{ ref('int_ga4_funnel') }}
    group by session_date, deepest_funnel_stage, funnel_stage_depth
),

final as (
    select
        session_date,
        deepest_funnel_stage,
        funnel_stage_depth,

        -- Session counts
        total_sessions,
        unique_users,

        -- Funnel stage metrics
        sessions_reached_homepage,
        sessions_reached_plp,
        sessions_reached_pdp,
        sessions_reached_cart,
        sessions_reached_checkout,
        sessions_reached_purchase,

        -- Dropoff metrics
        sessions_dropped_at_homepage,
        sessions_dropped_at_plp,
        sessions_dropped_at_pdp,
        sessions_dropped_at_cart,
        sessions_dropped_at_checkout,

        -- Conversion counts
        converted_sessions,

        -- Conversion rates (percentage)
        case when sessions_reached_homepage > 0
            then round(cast(sessions_reached_plp as float64) / sessions_reached_homepage * 100, 2)
            else 0
        end as homepage_to_plp_rate,

        case when sessions_reached_plp > 0
            then round(cast(sessions_reached_pdp as float64) / sessions_reached_plp * 100, 2)
            else 0
        end as plp_to_pdp_rate,

        case when sessions_reached_pdp > 0
            then round(cast(sessions_reached_cart as float64) / sessions_reached_pdp * 100, 2)
            else 0
        end as pdp_to_cart_rate,

        case when sessions_reached_cart > 0
            then round(cast(sessions_reached_checkout as float64) / sessions_reached_cart * 100, 2)
            else 0
        end as cart_to_checkout_rate,

        case when sessions_reached_checkout > 0
            then round(cast(sessions_reached_purchase as float64) / sessions_reached_checkout * 100, 2)
            else 0
        end as checkout_to_purchase_rate,

        -- Overall conversion rate (sessions → purchase)
        case when total_sessions > 0
            then round(cast(converted_sessions as float64) / total_sessions * 100, 2)
            else 0
        end as overall_conversion_rate,

        -- Dropoff rates (percentage)
        case when sessions_reached_homepage > 0
            then round(cast(sessions_dropped_at_homepage as float64) / sessions_reached_homepage * 100, 2)
            else 0
        end as homepage_dropoff_rate,

        case when sessions_reached_plp > 0
            then round(cast(sessions_dropped_at_plp as float64) / sessions_reached_plp * 100, 2)
            else 0
        end as plp_dropoff_rate,

        case when sessions_reached_pdp > 0
            then round(cast(sessions_dropped_at_pdp as float64) / sessions_reached_pdp * 100, 2)
            else 0
        end as pdp_dropoff_rate,

        case when sessions_reached_cart > 0
            then round(cast(sessions_dropped_at_cart as float64) / sessions_reached_cart * 100, 2)
            else 0
        end as cart_dropoff_rate,

        case when sessions_reached_checkout > 0
            then round(cast(sessions_dropped_at_checkout as float64) / sessions_reached_checkout * 100, 2)
            else 0
        end as checkout_dropoff_rate,

        -- Revenue metrics
        round(total_transaction_value, 2) as total_revenue,
        case when converted_sessions > 0
            then round(total_transaction_value / converted_sessions, 2)
            else 0
        end as avg_order_value,

        -- Engagement metrics
        round(avg_session_duration_minutes, 2) as avg_session_duration_minutes,
        round(avg_events_per_session, 2) as avg_events_per_session,
        round(avg_pdp_views_per_session, 2) as avg_pdp_views_per_session

    from daily_sessions
)

select * from final
