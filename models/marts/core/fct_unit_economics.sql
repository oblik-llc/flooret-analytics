{{
    config(
        materialized='table',
        partition_by={"field": "order_date", "data_type": "date", "granularity": "day"},
        cluster_by=['store', 'order_id']
    )
}}

/*
    Order-Level Unit Economics

    Purpose:
        Calculates order-level profitability with available cost data.
        Shows contribution margin before COGS (revenue - shipping - allocated ad spend).

    Grain: order_id (order level)

    CRITICAL LIMITATION (YELLOW Metric):
        ❌ COGS (Cost of Goods Sold) data is NOT AVAILABLE
        ❌ Cannot calculate true gross margin, contribution margin, or net profit
        ❌ This model calculates "Revenue - Variable Costs" only

    Available Costs:
        ✅ Shipping cost (from Freightview shipments)
        ✅ Ad spend (Facebook + Google Ads, allocated to new customers)
        ✅ Discounts (from Shopify orders)
        ✅ Refunds (from Shopify)

    Missing Costs (RED Metrics):
        ❌ Product COGS (raw materials, manufacturing, landed cost)
        ❌ Warehouse labor (pick, pack, quality control)
        ❌ Payment processing fees (Stripe/PayPal 2.9% + $0.30)
        ❌ Packaging materials
        ❌ Returns processing costs
        ❌ Customer service costs

    Calculated Metrics:
        - Gross revenue (subtotal before discounts)
        - Net sales (subtotal after discounts, before shipping/tax)
        - Total variable costs (shipping + ad spend allocation)
        - Contribution margin before COGS
        - Contribution margin % (% of net sales remaining after variable costs)

    Business Questions This CAN Answer:
        - Which orders have highest contribution margin?
        - What is CAC payback period (time to recover ad spend)?
        - How do shipping costs impact profitability by region?
        - What is the impact of discounts on economics?

    Business Questions This CANNOT Answer (Need COGS):
        - What is true order profitability?
        - Which SKUs are profitable vs loss leaders?
        - What is break-even volume?
        - Should we raise/lower prices?

    Usage:
        - Order-level profitability analysis (with limitations documented)
        - CAC payback analysis
        - Discount effectiveness
        - Regional profitability (shipping cost differences)
        - Identify high-cost orders for operational improvement
*/

with order_base as (
    select
        order_id,
        email,
        order_date,
        store,
        order_type,

        -- Revenue metrics
        subtotal_price as gross_revenue,
        total_discounts as discount_amount,
        subtotal_price - total_discounts as net_sales,
        total_tax,
        total_tip_received,

        -- Customer context
        customer_status,
        lifetime_product_revenue,
        salesperson,

        -- Geography
        shipping_state,
        shipping_country

    from {{ ref('fct_orders') }}
    where order_type = 'Product Order'  -- unit economics for product orders only
),

shipping_costs as (
    select
        order_id,
        sum(shipping_cost) as total_shipping_cost,
        count(distinct shipment_id) as shipment_count,
        avg(actual_transit_days) as avg_transit_days,
        sum(case when is_on_time = false then 1 else 0 end) as late_shipments

    from {{ ref('fct_shipments') }}
    where order_id is not null
    group by order_id
),

daily_ad_spend as (
    select
        date_day,
        store,
        sum(total_ad_spend) as total_ad_spend,
        sum(new_customers) as new_customers

    from {{ ref('fct_daily_performance') }}
    where new_customers > 0  -- only days with acquisitions
    group by date_day, store
),

ad_spend_allocation as (
    select
        o.order_id,
        o.email,
        o.order_date,
        o.store,
        o.customer_status,

        -- Allocate ad spend to new customers only
        case
            when o.customer_status in ('New Customer', 'New Customer Sample')
                and a.new_customers > 0
            then round(a.total_ad_spend / a.new_customers, 2)
            else 0
        end as allocated_ad_spend

    from order_base o
    left join daily_ad_spend a
        on o.order_date = a.date_day
        and o.store = a.store
),

final as (
    select
        o.order_id,
        o.email,
        o.order_date,
        o.store,
        o.order_type,
        o.customer_status,
        o.salesperson,
        o.shipping_state,
        o.shipping_country,

        -- Revenue metrics
        round(o.gross_revenue, 2) as gross_revenue,
        round(o.discount_amount, 2) as discount_amount,
        round(o.net_sales, 2) as net_sales,

        -- Discount rate
        case when o.gross_revenue > 0
            then round(o.discount_amount / o.gross_revenue * 100, 2)
            else 0
        end as discount_rate_pct,

        -- Cost components
        round(coalesce(s.total_shipping_cost, 0), 2) as shipping_cost,
        round(coalesce(a.allocated_ad_spend, 0), 2) as allocated_ad_spend,

        -- Total variable costs (shipping + ad spend)
        round(
            coalesce(s.total_shipping_cost, 0) + coalesce(a.allocated_ad_spend, 0),
            2
        ) as total_variable_costs,

        -- ⚠️ INCOMPLETE: Contribution margin BEFORE COGS
        round(
            o.net_sales
            - coalesce(s.total_shipping_cost, 0)
            - coalesce(a.allocated_ad_spend, 0),
            2
        ) as contribution_margin_before_cogs,

        -- Contribution margin % (of net sales)
        case when o.net_sales > 0
            then round(
                (o.net_sales
                 - coalesce(s.total_shipping_cost, 0)
                 - coalesce(a.allocated_ad_spend, 0))
                / o.net_sales * 100,
                2
            )
            else 0
        end as contribution_margin_pct,

        -- Cost ratios (as % of net sales)
        case when o.net_sales > 0
            then round(coalesce(s.total_shipping_cost, 0) / o.net_sales * 100, 2)
            else 0
        end as shipping_cost_pct,

        case when o.net_sales > 0
            then round(coalesce(a.allocated_ad_spend, 0) / o.net_sales * 100, 2)
            else 0
        end as ad_spend_pct,

        -- Shipment metrics
        coalesce(s.shipment_count, 0) as shipment_count,
        s.avg_transit_days,
        coalesce(s.late_shipments, 0) as late_shipments,

        -- Lifetime context
        round(o.lifetime_product_revenue, 2) as lifetime_product_revenue

    from order_base o
    left join shipping_costs s on o.order_id = s.order_id
    left join ad_spend_allocation a on o.order_id = a.order_id
)

select * from final
