{{
    config(
        materialized='table',
        partition_by={
            "field": "first_sample_order_date",
            "data_type": "date",
            "granularity": "month"
        },
        cluster_by=['sample_order_type', 'conversion_ind', 'cohort_month']
    )
}}

/*
    Sample-to-Product Conversion Analysis

    Purpose:
        Tracks customer journey from sample orders to product purchases with
        detailed conversion metrics at email and household levels.

    Optimization Notes:
        - Combines first_sample and first_product order lookups into single scan
        - Uses int_customer_funnel (materialized table) for funnel metrics
        - Aggregates product orders by window in single pass
*/

with

customer_funnel as (
    select * from {{ ref('int_customer_funnel') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

-- OPTIMIZED: Single scan to get both first sample and first product order details
first_orders as (
    select
        email,
        -- First sample order fields
        max(case when is_first_sample_order = 1 then order_id end) as first_sample_order_id,
        max(case when is_first_sample_order = 1 then store end) as first_sample_store,
        max(case when is_first_sample_order = 1 then salesperson end) as first_sample_salesperson,
        max(case when is_first_sample_order = 1 then sample_quantity end) as first_sample_quantity,
        max(case when is_first_sample_order = 1 then sample_revenue end) as first_sample_revenue,
        max(case when is_first_sample_order = 1 then shipping_state end) as first_sample_shipping_state,
        max(case when is_first_sample_order = 1 then shipping_state_code end) as first_sample_shipping_state_code,

        -- First product order fields
        max(case when is_first_product_order = 1 then order_id end) as first_product_order_id,
        max(case when is_first_product_order = 1 then store end) as first_product_store,
        max(case when is_first_product_order = 1 then salesperson end) as first_product_salesperson,
        max(case when is_first_product_order = 1 then product_quantity end) as first_product_quantity,
        max(case when is_first_product_order = 1 then product_revenue end) as first_product_revenue,
        max(case when is_first_product_order = 1 then shipping_state end) as first_product_shipping_state,
        max(case when is_first_product_order = 1 then shipping_state_code end) as first_product_shipping_state_code

    from {{ ref('fct_orders') }}
    where is_first_sample_order = 1 or is_first_product_order = 1
    group by email
),

-- Count product orders within windows after first sample
-- Join with funnel to get first_sample_order_date (avoids self-referencing fct_orders column)
product_orders_by_window as (
    select
        o.email,
        count(distinct case when date_diff(o.order_date, f.first_sample_order_date, day) <= 15 then o.order_id end) as product_orders_within_15d,
        count(distinct case when date_diff(o.order_date, f.first_sample_order_date, day) <= 30 then o.order_id end) as product_orders_within_30d,
        count(distinct case when date_diff(o.order_date, f.first_sample_order_date, day) <= 60 then o.order_id end) as product_orders_within_60d,
        count(distinct case when date_diff(o.order_date, f.first_sample_order_date, day) <= 120 then o.order_id end) as product_orders_within_120d,
        sum(case when date_diff(o.order_date, f.first_sample_order_date, day) <= 60 then o.product_revenue else 0 end) as product_revenue_within_60d

    from {{ ref('fct_orders') }} o
    inner join customer_funnel f on o.email = f.email
    where o.is_product_order = 1
        and f.first_sample_order_date is not null
    group by o.email
),

final as (
    select
        -- Primary key
        funnel.email,

        -- Funnel dates (email-based)
        funnel.first_order_date,
        funnel.first_sample_order_date,
        funnel.first_product_order_date,
        funnel.first_cut_order_date,
        funnel.first_plank_order_date,

        -- Conversion timing (email-based)
        funnel.days_to_order,
        funnel.days_cut_to_order,
        funnel.days_plank_to_order,
        funnel.days_cut_to_plank,

        -- Conversion indicators (email-based)
        funnel.conversion_ind,
        funnel.converted_within_15d,
        funnel.converted_within_30d,
        funnel.converted_within_60d,
        funnel.converted_within_120d,

        -- Household identification (NEW)
        funnel.household_id,
        funnel.household_email_count,

        -- Household conversion dates (NEW)
        funnel.household_first_order_date,
        funnel.household_first_sample_order_date,
        funnel.household_first_product_order_date,
        funnel.household_first_cut_order_date,
        funnel.household_first_plank_order_date,

        -- Household conversion timing (NEW)
        funnel.household_days_to_order,
        funnel.household_days_cut_to_order,
        funnel.household_days_plank_to_order,
        funnel.household_days_cut_to_plank,

        -- Household conversion indicators (NEW)
        funnel.household_conversion_ind,
        funnel.household_converted_within_15d,
        funnel.household_converted_within_30d,
        funnel.household_converted_within_60d,
        funnel.household_converted_within_120d,

        -- Hybrid conversion (NEW - email OR household)
        funnel.hybrid_conversion_ind,

        -- Sample order classification
        funnel.sample_order_type,
        funnel.cohort_month,

        -- First sample order details
        first_orders.first_sample_order_id,
        first_orders.first_sample_store,
        first_orders.first_sample_salesperson,
        first_orders.first_sample_quantity,
        first_orders.first_sample_revenue,
        first_orders.first_sample_shipping_state,
        first_orders.first_sample_shipping_state_code,

        -- First product order details (null if no conversion)
        first_orders.first_product_order_id,
        first_orders.first_product_store,
        first_orders.first_product_salesperson,
        first_orders.first_product_quantity,
        first_orders.first_product_revenue,
        first_orders.first_product_shipping_state,
        first_orders.first_product_shipping_state_code,

        -- Product orders by window
        coalesce(windows.product_orders_within_15d, 0) as product_orders_within_15d,
        coalesce(windows.product_orders_within_30d, 0) as product_orders_within_30d,
        coalesce(windows.product_orders_within_60d, 0) as product_orders_within_60d,
        coalesce(windows.product_orders_within_120d, 0) as product_orders_within_120d,
        coalesce(windows.product_revenue_within_60d, 0) as product_revenue_within_60d,

        -- Customer attributes (from dim_customers)
        customers.customer_group,
        customers.customer_type,
        customers.primary_shipping_state,
        customers.primary_store,

        -- Lifetime metrics (final)
        customers.lifetime_product_orders,
        customers.lifetime_sample_orders,
        customers.lifetime_product_revenue,
        customers.lifetime_sample_revenue,
        customers.lifetime_total_revenue,

        -- Customer segment
        customers.customer_segment,

        -- Conversion efficiency metrics
        case
            when first_orders.first_product_revenue is not null
                and first_orders.first_sample_revenue > 0
            then first_orders.first_product_revenue / first_orders.first_sample_revenue
            else null
        end as sample_to_product_revenue_ratio,

        -- Conversion window bucket (for cohort analysis - email-based)
        case
            when funnel.days_to_order is null then 'No Conversion'
            when funnel.days_to_order <= 15 then '0-15 days'
            when funnel.days_to_order <= 30 then '16-30 days'
            when funnel.days_to_order <= 60 then '31-60 days'
            when funnel.days_to_order <= 120 then '61-120 days'
            else '120+ days'
        end as conversion_window_bucket,

        -- Household conversion window bucket (NEW)
        case
            when funnel.household_days_to_order is null then 'No Conversion'
            when funnel.household_days_to_order <= 15 then '0-15 days'
            when funnel.household_days_to_order <= 30 then '16-30 days'
            when funnel.household_days_to_order <= 60 then '31-60 days'
            when funnel.household_days_to_order <= 120 then '61-120 days'
            else '120+ days'
        end as household_conversion_window_bucket,

        -- Hybrid conversion window bucket (use earliest conversion: email or household)
        case
            when funnel.hybrid_conversion_ind = 0 then 'No Conversion'
            when least(coalesce(funnel.days_to_order, 999999), coalesce(funnel.household_days_to_order, 999999)) <= 15 then '0-15 days'
            when least(coalesce(funnel.days_to_order, 999999), coalesce(funnel.household_days_to_order, 999999)) <= 30 then '16-30 days'
            when least(coalesce(funnel.days_to_order, 999999), coalesce(funnel.household_days_to_order, 999999)) <= 60 then '31-60 days'
            when least(coalesce(funnel.days_to_order, 999999), coalesce(funnel.household_days_to_order, 999999)) <= 120 then '61-120 days'
            else '120+ days'
        end as hybrid_conversion_window_bucket

    from customer_funnel as funnel
    inner join customers
        on funnel.email = customers.email
    left join first_orders
        on funnel.email = first_orders.email
    left join product_orders_by_window as windows
        on funnel.email = windows.email

    -- Only include customers who have ordered samples
    where funnel.first_sample_order_date is not null
)

select * from final
