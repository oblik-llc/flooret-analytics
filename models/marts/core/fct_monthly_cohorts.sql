{{
    config(
        materialized='table',
        partition_by={"field": "cohort_month", "data_type": "date", "granularity": "month"},
        cluster_by=['months_since_first_order']
    )
}}

/*
    Monthly Customer Cohort Analysis - Simplified

    Purpose:
        Tracks customer cohorts by first order month, showing retention and LTV progression.

    Grain: cohort_month + months_since_first_order
*/

with customer_first_orders as (
    select
        email,
        date_trunc(first_product_order_date, month) as cohort_month,
        first_product_order_date,
        primary_store
    from {{ ref('dim_customers') }}
    where first_product_order_date is not null
),

-- Get cohort sizes (customers in month 0)
cohort_sizes as (
    select
        cohort_month,
        primary_store,
        count(distinct email) as cohort_size
    from customer_first_orders
    group by cohort_month, primary_store
),

-- Get customer monthly activity
customer_monthly_activity as (
    select
        c.email,
        c.cohort_month,
        c.primary_store,
        date_trunc(o.order_date, month) as order_month,
        date_diff(
            date_trunc(o.order_date, month),
            c.cohort_month,
            month
        ) as months_since_first_order,
        count(distinct o.order_id) as orders,
        sum(o.net_sales) as revenue

    from customer_first_orders c
    inner join {{ ref('fct_orders') }} o
        on c.email = o.email
    where o.order_type = 'Product Order'
    group by 1, 2, 3, 4, 5
),

-- Aggregate to cohort-month level
cohort_monthly as (
    select
        cohort_month,
        primary_store,
        months_since_first_order,
        count(distinct email) as active_customers,
        sum(orders) as total_orders,
        sum(revenue) as cohort_revenue

    from customer_monthly_activity
    group by cohort_month, primary_store, months_since_first_order
),

-- Join with cohort sizes
with_sizes as (
    select
        cm.*,
        cs.cohort_size
    from cohort_monthly cm
    inner join cohort_sizes cs
        on cm.cohort_month = cs.cohort_month
        and cm.primary_store = cs.primary_store
),

final as (
    select
        cohort_month,
        primary_store,
        months_since_first_order,
        cohort_size,
        active_customers,

        -- Retention rate
        case when cohort_size > 0
            then round(cast(active_customers as float64) / cohort_size * 100, 2)
            else 0
        end as retention_rate,

        -- Revenue metrics
        round(cohort_revenue, 2) as cohort_revenue,

        -- Per-customer metrics
        case when active_customers > 0
            then round(cohort_revenue / active_customers, 2)
            else 0
        end as avg_revenue_per_active_customer,

        case when cohort_size > 0
            then round(cohort_revenue / cohort_size, 2)
            else 0
        end as avg_revenue_per_cohort_customer,

        total_orders,

        -- Cumulative LTV
        sum(cohort_revenue) over (
            partition by cohort_month, primary_store
            order by months_since_first_order
            rows between unbounded preceding and current row
        ) as cumulative_ltv,

        -- Calendar month for visualization
        date_add(cohort_month, interval months_since_first_order month) as calendar_month

    from with_sizes
)

select * from final
