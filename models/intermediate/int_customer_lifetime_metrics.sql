{{
    config(
        materialized='view'
    )
}}

with

orders_classified as (
    select * from {{ ref('int_order_classification') }}
),

-- Calculate lifetime metrics using window functions partitioned by email
-- (business_rules.md section 11: Lifetime Metrics)
lifetime_metrics as (
    select
        order_id,
        email,
        processed_at,
        order_date,
        store,
        is_product_order,
        is_sample_order,
        product_revenue,
        sample_revenue,
        net_sales,

        -- Lifetime order counts (running total)
        sum(is_product_order) over (
            partition by email
            order by processed_at, order_id
            rows between unbounded preceding and current row
        ) as lifetime_product_orders,

        sum(is_sample_order) over (
            partition by email
            order by processed_at, order_id
            rows between unbounded preceding and current row
        ) as lifetime_sample_orders,

        count(*) over (
            partition by email
            order by processed_at, order_id
            rows between unbounded preceding and current row
        ) as lifetime_total_orders,

        -- Lifetime revenue (running total)
        sum(product_revenue) over (
            partition by email
            order by processed_at, order_id
            rows between unbounded preceding and current row
        ) as lifetime_product_revenue,

        sum(sample_revenue) over (
            partition by email
            order by processed_at, order_id
            rows between unbounded preceding and current row
        ) as lifetime_sample_revenue,

        sum(net_sales) over (
            partition by email
            order by processed_at, order_id
            rows between unbounded preceding and current row
        ) as lifetime_total_revenue,

        -- Order sequence numbers
        row_number() over (
            partition by email
            order by processed_at, order_id
        ) as order_sequence_number,

        row_number() over (
            partition by email, is_product_order
            order by processed_at, order_id
        ) as product_order_sequence_number,

        row_number() over (
            partition by email, is_sample_order
            order by processed_at, order_id
        ) as sample_order_sequence_number

    from orders_classified
    where email is not null  -- exclude orders without email
),

-- Join back to orders_classified to get all fields
final as (
    select
        orders.*,
        metrics.lifetime_product_orders,
        metrics.lifetime_sample_orders,
        metrics.lifetime_total_orders,
        metrics.lifetime_product_revenue,
        metrics.lifetime_sample_revenue,
        metrics.lifetime_total_revenue,
        metrics.order_sequence_number,
        metrics.product_order_sequence_number,
        metrics.sample_order_sequence_number,

        -- Customer status flags (business_rules.md section 8)
        case when metrics.order_sequence_number = 1 then 1 else 0 end as is_first_order,
        case when metrics.product_order_sequence_number = 1 and orders.is_product_order = 1 then 1 else 0 end as is_first_product_order,
        case when metrics.sample_order_sequence_number = 1 and orders.is_sample_order = 1 then 1 else 0 end as is_first_sample_order,

        -- Average order value to date
        metrics.lifetime_total_revenue / nullif(metrics.lifetime_total_orders, 0) as avg_order_value_to_date,

        -- Days since first order
        date_diff(orders.order_date, first_value(orders.order_date) over (partition by orders.email order by orders.processed_at, orders.order_id), day) as days_since_first_order

    from orders_classified as orders
    inner join lifetime_metrics as metrics
        on orders.order_id = metrics.order_id
)

select * from final
