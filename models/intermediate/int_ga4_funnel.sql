{{
    config(
        materialized='view'
    )
}}

/*
    Website Conversion Funnel Analysis

    Purpose:
        Tracks user progression through the e-commerce funnel using GA4 event sequences.
        Calculates conversion rates and dropoff at each funnel stage.

    Grain: user_pseudo_id + ga_session_id (session level)

    Funnel Stages:
        1. Homepage Visit
        2. Product List Page (PLP) View
        3. Product Detail Page (PDP) View
        4. Add to Cart
        5. Begin Checkout
        6. Purchase

    Business Logic:
        - Session is the unit of analysis (users can have multiple sessions)
        - Any event in the category counts (e.g., viewing any PDP = stage complete)
        - Later stages imply earlier stages (purchase implies all previous stages)
        - Includes session-level aggregations for analysis
*/

with session_events as (
    select
        user_pseudo_id,
        ga_session_id,
        min(event_timestamp_pt) as session_start_time,
        max(event_timestamp_pt) as session_end_time,

        -- Funnel stage indicators (1 if stage reached, 0 if not)
        max(case when page_type = 'homepage' then 1 else 0 end) as reached_homepage,
        max(case when page_type = 'product_list' then 1 else 0 end) as reached_plp,
        max(case when page_type = 'product_detail' then 1 else 0 end) as reached_pdp,
        max(is_add_to_cart) as reached_add_to_cart,
        max(is_begin_checkout) as reached_begin_checkout,
        max(is_purchase) as reached_purchase,

        -- Event counts by stage
        count(case when page_type = 'homepage' then 1 end) as homepage_views,
        count(case when page_type = 'product_list' then 1 end) as plp_views,
        count(case when page_type = 'product_detail' then 1 end) as pdp_views,
        sum(is_add_to_cart) as add_to_cart_events,
        sum(is_begin_checkout) as begin_checkout_events,
        sum(is_purchase) as purchase_events,

        -- Purchase details (only populated if reached_purchase = 1)
        max(case when is_purchase = 1 then transaction_id end) as transaction_id,
        max(case when is_purchase = 1 then transaction_value end) as transaction_value,

        -- Session metadata
        count(*) as total_events,
        count(distinct event_name) as unique_event_types

    from {{ ref('stg_ga4__events') }}
    where user_pseudo_id is not null
        and ga_session_id is not null
    group by user_pseudo_id, ga_session_id
),

funnel_classification as (
    select
        *,

        -- Session duration in minutes
        timestamp_diff(session_end_time, session_start_time, minute) as session_duration_minutes,

        -- Determine deepest funnel stage reached
        case
            when reached_purchase = 1 then 'Purchase'
            when reached_begin_checkout = 1 then 'Begin Checkout'
            when reached_add_to_cart = 1 then 'Add to Cart'
            when reached_pdp = 1 then 'Product Detail'
            when reached_plp = 1 then 'Product List'
            when reached_homepage = 1 then 'Homepage'
            else 'Other'
        end as deepest_funnel_stage,

        -- Funnel stage depth (numeric for sorting/aggregation)
        case
            when reached_purchase = 1 then 6
            when reached_begin_checkout = 1 then 5
            when reached_add_to_cart = 1 then 4
            when reached_pdp = 1 then 3
            when reached_plp = 1 then 2
            when reached_homepage = 1 then 1
            else 0
        end as funnel_stage_depth,

        -- Conversion flags
        case when reached_purchase = 1 then 1 else 0 end as is_converted_session,

        -- Dropoff indicators (reached a stage but didn't proceed to next)
        case when reached_homepage = 1 and reached_plp = 0 then 1 else 0 end as dropped_at_homepage,
        case when reached_plp = 1 and reached_pdp = 0 then 1 else 0 end as dropped_at_plp,
        case when reached_pdp = 1 and reached_add_to_cart = 0 then 1 else 0 end as dropped_at_pdp,
        case when reached_add_to_cart = 1 and reached_begin_checkout = 0 then 1 else 0 end as dropped_at_cart,
        case when reached_begin_checkout = 1 and reached_purchase = 0 then 1 else 0 end as dropped_at_checkout,

        -- Session date for aggregations
        date(session_start_time) as session_date

    from session_events
)

select * from funnel_classification
