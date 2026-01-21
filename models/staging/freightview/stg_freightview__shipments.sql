{{
    config(
        materialized='view'
    )
}}

with

source as (
    select * from {{ source('ft_freightview', 'shipment') }}
),

renamed as (
    select
        -- identifiers
        id as shipment_id,

        -- timestamps
        datetime(created_date, 'America/Los_Angeles') as created_at,
        date(pickup_date) as pickup_date,
        datetime(tracking_delivery_date_actual, 'America/Los_Angeles') as actual_delivery_at,
        date(tracking_delivery_date_actual) as actual_delivery_date,

        -- shipment details
        status,
        tracking_status,

        -- carrier and service
        rate_carrier as carrier,
        rate_service_type as service_type,
        rate_transit_days as estimated_transit_days,

        -- costs
        rate_total as quoted_rate,
        invoice_amount as invoiced_amount,
        coalesce(invoice_amount, rate_total) as shipping_cost,

        -- origin
        origin_city,
        origin_state,

        -- destination
        destination_city,
        destination_state,

        -- calculated fields
        case
            when tracking_delivery_date_actual is not null and pickup_date is not null
            then date_diff(
                date(tracking_delivery_date_actual),
                date(pickup_date),
                day
            )
            else null
        end as actual_transit_days,

        case
            when tracking_delivery_date_actual is not null
                and pickup_date is not null
                and rate_transit_days is not null
            then date_diff(
                date(tracking_delivery_date_actual),
                date(pickup_date),
                day
            ) <= rate_transit_days
            else null
        end as is_on_time

    from source
),

final as (
    select
        *,

        -- cost variance
        case
            when quoted_rate is not null and invoiced_amount is not null
            then invoiced_amount - quoted_rate
            else null
        end as cost_variance,

        -- transit time variance
        case
            when actual_transit_days is not null and estimated_transit_days is not null
            then actual_transit_days - estimated_transit_days
            else null
        end as transit_variance_days

    from renamed
)

select * from final
