{{
    config(
        materialized='table',
        partition_by={
            "field": "pickup_date",
            "data_type": "date",
            "granularity": "day"
        },
        cluster_by=['carrier', 'origin_state', 'destination_state']
    )
}}

with

shipments as (
    select * from {{ ref('stg_freightview__shipments') }}
),

final as (
    select
        -- Identifiers
        shipment_id,

        -- Dates
        pickup_date,
        actual_delivery_date,
        extract(year from pickup_date) as pickup_year,
        extract(month from pickup_date) as pickup_month,
        extract(quarter from pickup_date) as pickup_quarter,
        date_trunc(pickup_date, week) as pickup_week_start_date,
        date_trunc(pickup_date, month) as pickup_month_start_date,

        -- Shipment details
        status,
        tracking_status,
        carrier,
        service_type,

        -- Transit metrics
        estimated_transit_days,
        actual_transit_days,
        transit_variance_days,
        is_on_time,

        -- Cost metrics
        quoted_rate,
        invoiced_amount,
        shipping_cost,
        cost_variance,

        -- Locations
        origin_city,
        origin_state,
        destination_city,
        destination_state,

        -- Performance flags
        case when is_on_time = true then 1 else 0 end as on_time_delivery_count,
        case when is_on_time = false then 1 else 0 end as late_delivery_count,
        case when cost_variance > 0 then 1 else 0 end as over_budget_count,
        case when cost_variance < 0 then 1 else 0 end as under_budget_count,

        -- Timestamps
        created_at,
        actual_delivery_at

    from shipments
)

select * from final
