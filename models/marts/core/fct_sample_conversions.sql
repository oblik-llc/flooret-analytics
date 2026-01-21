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

with

customer_funnel as (
    select * from {{ ref('int_customer_funnel') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

-- Get first sample order details
first_sample_orders as (
    select
        email,
        order_id as first_sample_order_id,
        store as first_sample_store,
        salesperson as first_sample_salesperson,
        sample_quantity as first_sample_quantity,
        sample_revenue as first_sample_revenue,
        shipping_state as first_sample_shipping_state,
        shipping_state_code as first_sample_shipping_state_code

    from {{ ref('fct_orders') }}
    where is_first_sample_order = 1
),

-- Get first product order details
first_product_orders as (
    select
        email,
        order_id as first_product_order_id,
        store as first_product_store,
        salesperson as first_product_salesperson,
        product_quantity as first_product_quantity,
        product_revenue as first_product_revenue,
        shipping_state as first_product_shipping_state,
        shipping_state_code as first_product_shipping_state_code

    from {{ ref('fct_orders') }}
    where is_first_product_order = 1
),

-- Count product orders within windows after first sample
product_orders_by_window as (
    select
        email,
        count(distinct case when date_diff(order_date, first_sample_order_date, day) <= 15 then order_id end) as product_orders_within_15d,
        count(distinct case when date_diff(order_date, first_sample_order_date, day) <= 30 then order_id end) as product_orders_within_30d,
        count(distinct case when date_diff(order_date, first_sample_order_date, day) <= 60 then order_id end) as product_orders_within_60d,
        count(distinct case when date_diff(order_date, first_sample_order_date, day) <= 120 then order_id end) as product_orders_within_120d,
        sum(case when date_diff(order_date, first_sample_order_date, day) <= 60 then product_revenue else 0 end) as product_revenue_within_60d

    from {{ ref('fct_orders') }}
    where is_product_order = 1
        and first_sample_order_date is not null
    group by 1
),

final as (
    select
        -- Primary key
        funnel.email,

        -- Funnel dates
        funnel.first_order_date,
        funnel.first_sample_order_date,
        funnel.first_product_order_date,
        funnel.first_cut_order_date,
        funnel.first_plank_order_date,

        -- Conversion timing
        funnel.days_to_order,
        funnel.days_cut_to_order,
        funnel.days_plank_to_order,
        funnel.days_cut_to_plank,

        -- Conversion indicators
        funnel.conversion_ind,
        funnel.converted_within_15d,
        funnel.converted_within_30d,
        funnel.converted_within_60d,
        funnel.converted_within_120d,

        -- Sample order classification
        funnel.sample_order_type,
        funnel.cohort_month,

        -- First sample order details
        first_sample.first_sample_order_id,
        first_sample.first_sample_store,
        first_sample.first_sample_salesperson,
        first_sample.first_sample_quantity,
        first_sample.first_sample_revenue,
        first_sample.first_sample_shipping_state,
        first_sample.first_sample_shipping_state_code,

        -- First product order details (null if no conversion)
        first_product.first_product_order_id,
        first_product.first_product_store,
        first_product.first_product_salesperson,
        first_product.first_product_quantity,
        first_product.first_product_revenue,
        first_product.first_product_shipping_state,
        first_product.first_product_shipping_state_code,

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
            when first_product.first_product_revenue is not null
                and first_sample.first_sample_revenue > 0
            then first_product.first_product_revenue / first_sample.first_sample_revenue
            else null
        end as sample_to_product_revenue_ratio,

        -- Conversion window bucket (for cohort analysis)
        case
            when funnel.days_to_order is null then 'No Conversion'
            when funnel.days_to_order <= 15 then '0-15 days'
            when funnel.days_to_order <= 30 then '16-30 days'
            when funnel.days_to_order <= 60 then '31-60 days'
            when funnel.days_to_order <= 120 then '61-120 days'
            else '120+ days'
        end as conversion_window_bucket

    from customer_funnel as funnel
    inner join customers
        on funnel.email = customers.email
    left join first_sample_orders as first_sample
        on funnel.email = first_sample.email
    left join first_product_orders as first_product
        on funnel.email = first_product.email
    left join product_orders_by_window as windows
        on funnel.email = windows.email

    -- Only include customers who have ordered samples
    where funnel.first_sample_order_date is not null
)

select * from final
