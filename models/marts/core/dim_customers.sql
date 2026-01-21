{{
    config(
        materialized='table',
        cluster_by=['email', 'customer_group', 'customer_type']
    )
}}

with

customers as (
    select * from {{ ref('stg_shopify__customers') }}
),

customer_funnel as (
    select * from {{ ref('int_customer_funnel') }}
),

-- Get lifetime totals from most recent order per customer
customer_lifetime_final as (
    select
        email,
        max(lifetime_product_orders) as lifetime_product_orders,
        max(lifetime_sample_orders) as lifetime_sample_orders,
        max(lifetime_total_orders) as lifetime_total_orders,
        max(lifetime_product_revenue) as lifetime_product_revenue,
        max(lifetime_sample_revenue) as lifetime_sample_revenue,
        max(lifetime_total_revenue) as lifetime_total_revenue,
        max(order_date) as most_recent_order_date,
        min(order_date) as first_order_date

    from {{ ref('int_customer_lifetime_metrics') }}
    group by 1
),

-- Get primary shipping location from orders (most common state)
customer_primary_location as (
    select
        email,
        -- Use mode of shipping_state as primary location
        approx_top_count(shipping_state, 1)[offset(0)].value as primary_shipping_state,
        approx_top_count(shipping_state_code, 1)[offset(0)].value as primary_shipping_state_code,
        approx_top_count(shipping_city, 1)[offset(0)].value as primary_shipping_city

    from {{ ref('fct_orders') }}
    where shipping_state is not null
    group by 1
),

-- Determine primary store (where they order most)
customer_primary_store as (
    select
        email,
        approx_top_count(store, 1)[offset(0)].value as primary_store,
        count(distinct case when store = 'regular' then order_id end) as regular_order_count,
        count(distinct case when store = 'commercial' then order_id end) as commercial_order_count

    from {{ ref('fct_orders') }}
    group by 1
),

final as (
    select
        -- Primary key
        customers.email,

        -- Customer attributes from Shopify
        customers.customer_id,
        customers.first_name,
        customers.last_name,
        customers.phone,
        customers.customer_group,
        customers.customer_type,
        customers.account_state,
        customers.is_verified_email,

        -- Customer segmentation
        customers.store as source_store,  -- store where customer record is from
        store.primary_store,  -- store where they primarily shop
        store.regular_order_count,
        store.commercial_order_count,

        -- Timestamps
        customers.created_at as account_created_at,
        customers.first_order_at as shopify_first_order_at,
        customers.most_recent_order_at as shopify_most_recent_order_at,
        lifetime.first_order_date,
        lifetime.most_recent_order_date,

        -- Funnel dates (from int_customer_funnel)
        funnel.first_sample_order_date,
        funnel.first_product_order_date,
        funnel.first_cut_order_date,
        funnel.first_plank_order_date,
        funnel.days_to_order,
        funnel.days_cut_to_order,
        funnel.days_plank_to_order,
        funnel.sample_order_type,
        funnel.cohort_month,

        -- Conversion metrics
        funnel.conversion_ind,
        funnel.converted_within_15d,
        funnel.converted_within_30d,
        funnel.converted_within_60d,
        funnel.converted_within_120d,

        -- Lifetime metrics (from int_customer_lifetime_metrics final values)
        coalesce(lifetime.lifetime_product_orders, 0) as lifetime_product_orders,
        coalesce(lifetime.lifetime_sample_orders, 0) as lifetime_sample_orders,
        coalesce(lifetime.lifetime_total_orders, 0) as lifetime_total_orders,
        coalesce(lifetime.lifetime_product_revenue, 0) as lifetime_product_revenue,
        coalesce(lifetime.lifetime_sample_revenue, 0) as lifetime_sample_revenue,
        coalesce(lifetime.lifetime_total_revenue, 0) as lifetime_total_revenue,

        -- Calculated metrics
        case
            when lifetime.lifetime_total_orders > 0
            then lifetime.lifetime_total_revenue / lifetime.lifetime_total_orders
            else 0
        end as average_order_value,

        case
            when lifetime.lifetime_product_orders > 0
            then lifetime.lifetime_product_revenue / lifetime.lifetime_product_orders
            else 0
        end as average_product_order_value,

        -- Recency (days since last order)
        date_diff(current_date(), lifetime.most_recent_order_date, day) as days_since_last_order,

        -- Tenure (days since first order)
        date_diff(current_date(), lifetime.first_order_date, day) as customer_tenure_days,

        -- Location (primary shipping)
        location.primary_shipping_state,
        location.primary_shipping_state_code,
        location.primary_shipping_city,

        -- Marketing attributes
        customers.marketing_consent_state,
        customers.marketing_opt_in_level,

        -- Shopify lifetime metrics (for comparison/validation)
        customers.lifetime_count_orders as shopify_lifetime_orders,
        customers.lifetime_total_spent as shopify_lifetime_spent,
        customers.lifetime_total_refunded as shopify_lifetime_refunded,
        customers.avg_order_value as shopify_avg_order_value,

        -- Customer classification flags
        case when lifetime.lifetime_product_orders > 0 then 1 else 0 end as has_purchased_product,
        case when lifetime.lifetime_sample_orders > 0 then 1 else 0 end as has_ordered_samples,
        case when lifetime.lifetime_product_orders > 1 then 1 else 0 end as is_repeat_product_customer,

        -- Customer segment (RFM-like)
        case
            when lifetime.lifetime_product_revenue >= 5000 then 'High Value'
            when lifetime.lifetime_product_revenue >= 2000 then 'Medium Value'
            when lifetime.lifetime_product_revenue >= 500 then 'Low Value'
            when lifetime.lifetime_sample_orders > 0 and lifetime.lifetime_product_orders = 0 then 'Sample Only'
            else 'No Purchase'
        end as customer_segment

    from customers
    left join customer_funnel as funnel
        on customers.email = funnel.email
    left join customer_lifetime_final as lifetime
        on customers.email = lifetime.email
    left join customer_primary_location as location
        on customers.email = location.email
    left join customer_primary_store as store
        on customers.email = store.email
)

select * from final
