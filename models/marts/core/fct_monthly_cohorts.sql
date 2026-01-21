{{
    config(
        materialized='table',
        partition_by={"field": "cohort_month", "data_type": "date", "granularity": "month"},
        cluster_by=['months_since_first_order']
    )
}}

/*
    Monthly Customer Cohort Analysis

    Purpose:
        Tracks customer cohorts by first order month, showing retention and LTV progression.
        Enables cohort retention analysis, LTV projection, and customer value optimization.

    Grain: cohort_month + months_since_first_order (cohort-month-pair)

    Key Metrics:
        - Cohort size (customers in first month)
        - Active customers (customers who ordered in that relative month)
        - Retention rate (active / cohort size)
        - Cohort revenue (total revenue from cohort in that month)
        - Cumulative LTV (total lifetime revenue up to that month)
        - Average order value by cohort-month

    Business Logic:
        - Cohort defined by first PRODUCT order date (not sample orders)
        - Months_since_first_order: 0 = first order month, 1 = month after, etc.
        - Only includes customers with product orders (sample-only excluded)
        - Revenue is product revenue only (samples/accessories excluded)

    Usage:
        - Retention curve visualization
        - LTV projection models
        - Cohort comparison (e.g., 2024-01 vs 2024-06 retention)
        - Customer lifetime value forecasting
*/

with customer_first_orders as (
    select
        email,
        date_trunc(first_product_order_date, month) as cohort_month,
        first_product_order_date,
        store
    from {{ ref('dim_customers') }}
    where first_product_order_date is not null  -- exclude sample-only customers
),

customer_monthly_activity as (
    select
        c.email,
        c.cohort_month,
        c.first_product_order_date,
        c.store,
        date_trunc(o.order_date, month) as order_month,

        -- Calculate months since first order
        date_diff(
            date_trunc(o.order_date, month),
            c.cohort_month,
            month
        ) as months_since_first_order,

        -- Order metrics
        count(distinct o.order_id) as orders,
        sum(o.net_sales) as revenue,
        sum(case when o.order_type = 'Product Order' then o.net_sales else 0 end) as product_revenue

    from customer_first_orders c
    inner join {{ ref('fct_orders') }} o
        on c.email = o.email
    where o.order_type = 'Product Order'  -- only product orders for cohort analysis
    group by
        c.email,
        c.cohort_month,
        c.first_product_order_date,
        c.store,
        order_month,
        months_since_first_order
),

cohort_metrics as (
    select
        cohort_month,
        store,
        months_since_first_order,

        -- Cohort size (first month only, but repeated for each month row)
        count(distinct case when months_since_first_order = 0 then email end) over (
            partition by cohort_month, store
        ) as cohort_size,

        -- Active customers (customers who ordered in this relative month)
        count(distinct email) as active_customers,

        -- Order metrics
        sum(orders) as total_orders,
        sum(revenue) as cohort_revenue,
        sum(product_revenue) as cohort_product_revenue,

        -- Customer counts for percentile calculations
        count(distinct email) as customer_count

    from customer_monthly_activity
    group by cohort_month, store, months_since_first_order
),

final as (
    select
        cohort_month,
        store,
        months_since_first_order,

        -- Cohort sizing
        cohort_size,
        active_customers,

        -- Retention rate
        case when cohort_size > 0
            then round(cast(active_customers as float64) / cohort_size * 100, 2)
            else 0
        end as retention_rate,

        -- Revenue metrics
        round(cohort_revenue, 2) as cohort_revenue,
        round(cohort_product_revenue, 2) as cohort_product_revenue,

        -- Per-customer metrics
        case when active_customers > 0
            then round(cohort_revenue / active_customers, 2)
            else 0
        end as avg_revenue_per_active_customer,

        case when cohort_size > 0
            then round(cohort_revenue / cohort_size, 2)
            else 0
        end as avg_revenue_per_cohort_customer,

        -- Order metrics
        total_orders,
        case when active_customers > 0
            then round(cast(total_orders as float64) / active_customers, 2)
            else 0
        end as avg_orders_per_active_customer,

        -- Cumulative LTV (sum of all revenue from month 0 to current month)
        sum(cohort_revenue) over (
            partition by cohort_month, store
            order by months_since_first_order
            rows between unbounded preceding and current row
        ) as cumulative_ltv,

        -- Cumulative LTV per cohort customer
        round(
            sum(cohort_revenue) over (
                partition by cohort_month, store
                order by months_since_first_order
                rows between unbounded preceding and current row
            ) / cohort_size,
            2
        ) as cumulative_ltv_per_customer,

        -- Month-over-month metrics
        lag(active_customers) over (
            partition by cohort_month, store
            order by months_since_first_order
        ) as prev_month_active_customers,

        -- Calculate relative month date (for time series visualization)
        date_add(cohort_month, interval months_since_first_order month) as calendar_month

    from cohort_metrics
)

select * from final
order by cohort_month desc, store, months_since_first_order
