{{
    config(
        materialized='view'
    )
}}

/*
    Demand Forecasting Time Series Preparation

    Purpose:
        Prepares time series data for demand forecasting models. Aggregates historical
        sales with seasonality indicators, trend features, and lagged metrics.

    Grain: date_day + store + sku (daily SKU-level)

    Features Included:
        - Historical sales metrics (quantity, revenue, orders)
        - Calendar features (day of week, month, quarter, holiday flags)
        - Seasonality indicators (week of year, day of year)
        - Lagged features (7-day, 14-day, 28-day lag)
        - Rolling averages (7-day, 28-day, 90-day)
        - Trend features (days since first sale, sales velocity)
        - Marketing spend (proxy for demand drivers)

    Assumptions (YELLOW Metric):
        - No external demand signals (housing starts, macro indicators, weather)
        - No inventory constraints modeled
        - Assumes historical patterns predict future (may not capture disruptions)
        - No promotional calendar (relies on discount field from orders)

    Usage:
        - Input for time series forecasting models (Prophet, ARIMA, ML models)
        - Trend analysis and seasonality detection
        - SKU-level demand planning
*/

with daily_sku_sales as (
    select
        o.order_date as date_day,
        o.store,
        l.sku,
        l.line_item_type,
        l.color,

        -- Sales metrics
        sum(l.quantity) as quantity_sold,
        sum(l.total_price) as revenue,
        count(distinct o.order_id) as order_count,
        count(distinct o.email) as unique_customers,

        -- Average metrics
        avg(l.price) as avg_unit_price

    from {{ ref('fct_orders') }} o
    inner join {{ ref('fct_order_lines') }} l
        on o.order_id = l.order_id
    where l.line_item_type = 'Product'  -- forecast product demand only
        and o.order_type = 'Product Order'
        and l.sku is not null
    group by
        o.order_date,
        o.store,
        l.sku,
        l.line_item_type,
        l.color
),

calendar_features as (
    select
        *,

        -- Calendar features
        extract(dayofweek from date_day) as day_of_week,  -- 1 = Sunday, 7 = Saturday
        extract(day from date_day) as day_of_month,
        extract(week from date_day) as week_of_year,
        extract(month from date_day) as month_of_year,
        extract(quarter from date_day) as quarter_of_year,
        extract(year from date_day) as year,
        extract(dayofyear from date_day) as day_of_year,

        -- Weekend flag
        case when extract(dayofweek from date_day) in (1, 7) then 1 else 0 end as is_weekend,

        -- Month start/end flags
        case when extract(day from date_day) = 1 then 1 else 0 end as is_month_start,
        case when extract(day from date_day) = extract(day from last_day(date_day)) then 1 else 0 end as is_month_end,

        -- Major US holidays (simple approximation)
        case
            when extract(month from date_day) = 1 and extract(day from date_day) = 1 then 'New Years'
            when extract(month from date_day) = 7 and extract(day from date_day) = 4 then 'July 4th'
            when extract(month from date_day) = 12 and extract(day from date_day) = 25 then 'Christmas'
            when extract(month from date_day) = 11 and extract(dayofweek from date_day) = 5
                and extract(day from date_day) between 22 and 28 then 'Thanksgiving'
            -- Black Friday (day after Thanksgiving)
            when extract(month from date_day) = 11 and extract(dayofweek from date_day) = 6
                and extract(day from date_day) between 23 and 29 then 'Black Friday'
            -- Cyber Monday (Monday after Thanksgiving)
            when extract(month from date_day) = 11 and extract(dayofweek from date_day) = 2
                and extract(day from date_day) between 25 and 31 then 'Cyber Monday'
            else null
        end as holiday_name,

        case
            when extract(month from date_day) in (1, 7, 11, 12)
                and (extract(day from date_day) in (1, 4, 25)
                     or (extract(month from date_day) = 11 and extract(day from date_day) between 22 and 29))
            then 1
            else 0
        end as is_holiday_week

    from daily_sku_sales
),

lagged_features as (
    select
        *,

        -- Lagged sales (7, 14, 28 days ago)
        lag(quantity_sold, 7) over (partition by store, sku order by date_day) as quantity_sold_lag_7d,
        lag(quantity_sold, 14) over (partition by store, sku order by date_day) as quantity_sold_lag_14d,
        lag(quantity_sold, 28) over (partition by store, sku order by date_day) as quantity_sold_lag_28d,

        -- Rolling averages (7, 28, 90 days)
        avg(quantity_sold) over (
            partition by store, sku
            order by date_day
            rows between 6 preceding and current row
        ) as quantity_sold_avg_7d,

        avg(quantity_sold) over (
            partition by store, sku
            order by date_day
            rows between 27 preceding and current row
        ) as quantity_sold_avg_28d,

        avg(quantity_sold) over (
            partition by store, sku
            order by date_day
            rows between 89 preceding and current row
        ) as quantity_sold_avg_90d,

        -- Rolling standard deviation (for volatility)
        stddev(quantity_sold) over (
            partition by store, sku
            order by date_day
            rows between 27 preceding and current row
        ) as quantity_sold_stddev_28d,

        -- Days since first sale (trend feature)
        date_diff(
            date_day,
            min(date_day) over (partition by store, sku),
            day
        ) as days_since_first_sale,

        -- Days since last sale (recency)
        date_diff(
            date_day,
            lag(date_day) over (partition by store, sku order by date_day),
            day
        ) as days_since_last_sale

    from calendar_features
),

marketing_context as (
    select
        l.*,

        -- Join daily ad spend as demand driver
        coalesce(d.total_ad_spend, 0) as daily_ad_spend,
        coalesce(d.new_customers, 0) as daily_new_customers

    from lagged_features l
    left join {{ ref('fct_daily_performance') }} d
        on l.date_day = d.date_day
        and l.store = d.store
),

final as (
    select
        *,

        -- Sales velocity (7-day trend)
        case when quantity_sold_lag_7d > 0
            then round((quantity_sold - quantity_sold_lag_7d) / quantity_sold_lag_7d * 100, 2)
            else null
        end as quantity_change_pct_7d,

        -- Seasonality strength (current vs 28-day avg)
        case when quantity_sold_avg_28d > 0
            then round(quantity_sold / quantity_sold_avg_28d, 2)
            else null
        end as seasonality_index_28d,

        -- Volatility score (coefficient of variation)
        case when quantity_sold_avg_28d > 0 and quantity_sold_stddev_28d is not null
            then round(quantity_sold_stddev_28d / quantity_sold_avg_28d, 2)
            else null
        end as demand_volatility_cv

    from marketing_context
)

select * from final
