{{
    config(
        materialized='view'
    )
}}

with

orders_classified as (
    select * from {{ ref('int_order_classification') }}
),

order_lines as (
    select * from {{ ref('stg_shopify__order_lines') }}
),

-- Get product categories for each order from line items
-- This is used to determine "sample order type" (which categories were sampled)
order_categories as (
    select
        order_id,
        -- We'll need to implement product category logic here
        -- For now, using a placeholder based on SKU patterns from business_rules.md section 3
        max(case
            when sku like '%-S-%' or sku like '%-7210-%' then 'Signature'
            when sku like '%-B-%' or sku like '%-4805-%' then 'Base'
            when sku like '%-C-%' then 'Craftsman'
            when sku like '%-7-%' or sku like '%-7T-%' then 'Silvan Hardwood'
            else 'Other'
        end) as primary_category,

        -- Track which categories were sampled
        count(distinct case when line_item_type = 'Sample' and (sku like '%-S-%' or sku like '%-7210-%') then 1 end) as signature_sample_count,
        count(distinct case when line_item_type = 'Sample' and (sku like '%-B-%' or sku like '%-4805-%') then 1 end) as base_sample_count,
        count(distinct case when line_item_type = 'Sample' and sku like '%-C-%' then 1 end) as craftsman_sample_count,
        count(distinct case when line_item_type = 'Sample' and (sku like '%-7-%' or sku like '%-7T-%') then 1 end) as silvan_sample_count,

        -- Track which categories were purchased
        count(distinct case when line_item_type = 'Product' and (sku like '%-S-%' or sku like '%-7210-%') then 1 end) as signature_product_count,
        count(distinct case when line_item_type = 'Product' and (sku like '%-B-%' or sku like '%-4805-%') then 1 end) as base_product_count,
        count(distinct case when line_item_type = 'Product' and sku like '%-C-%' then 1 end) as craftsman_product_count,
        count(distinct case when line_item_type = 'Product' and (sku like '%-7-%' or sku like '%-7T-%') then 1 end) as silvan_product_count

    from order_lines
    group by 1
),

-- Calculate first order dates per customer (business_rules.md section 9)
customer_first_orders as (
    select
        email,

        -- First sample order (sample_quantity > 0 AND product_quantity = 0)
        min(case when is_sample_order = 1 then order_date end) as first_sample_order_date,
        min(case when is_sample_order = 1 then processed_at end) as first_sample_order_timestamp,

        -- First product order (product_quantity > 0)
        min(case when is_product_order = 1 then order_date end) as first_product_order_date,
        min(case when is_product_order = 1 then processed_at end) as first_product_order_timestamp,

        -- First cut sample order
        min(case when has_cut_samples = 1 then order_date end) as first_cut_order_date,

        -- First plank sample order
        min(case when has_plank_samples = 1 then order_date end) as first_plank_order_date,

        -- Overall first order
        min(order_date) as first_order_date,

        -- Conversion indicator (did they ever make a product purchase?)
        max(is_product_order) as has_ever_purchased_product

    from orders_classified
    where email is not null
        and email not like '%amazon%'  -- business_rules.md section 18: exclude Amazon marketplace
    group by 1
),

-- Calculate days to order and conversion windows (business_rules.md section 12)
customer_funnel_metrics as (
    select
        *,

        -- Days from sample to product order
        date_diff(first_product_order_date, first_sample_order_date, day) as days_to_order,
        date_diff(first_product_order_date, first_cut_order_date, day) as days_cut_to_order,
        date_diff(first_product_order_date, first_plank_order_date, day) as days_plank_to_order,
        date_diff(first_plank_order_date, first_cut_order_date, day) as days_cut_to_plank,

        -- Conversion window flags (did they convert within X days?)
        case when date_diff(first_product_order_date, first_sample_order_date, day) <= 15 then 1 else 0 end as converted_within_15d,
        case when date_diff(first_product_order_date, first_sample_order_date, day) <= 30 then 1 else 0 end as converted_within_30d,
        case when date_diff(first_product_order_date, first_sample_order_date, day) <= 60 then 1 else 0 end as converted_within_60d,
        case when date_diff(first_product_order_date, first_sample_order_date, day) <= 120 then 1 else 0 end as converted_within_120d,

        -- Conversion indicator
        case when has_ever_purchased_product = 1 then 1 else 0 end as conversion_ind

    from customer_first_orders
),

-- Determine sample order type based on which categories were sampled
-- This requires looking at all sample orders before first product order
sample_orders_before_purchase as (
    select
        o.email,
        sum(case when cat.signature_sample_count > 0 then 1 else 0 end) as signature_sample_orders,
        sum(case when cat.base_sample_count > 0 then 1 else 0 end) as base_sample_orders,
        sum(case when cat.craftsman_sample_count > 0 then 1 else 0 end) as craftsman_sample_orders,
        sum(case when cat.silvan_sample_count > 0 then 1 else 0 end) as silvan_sample_orders

    from orders_classified as o
    inner join order_categories as cat on o.order_id = cat.order_id
    inner join customer_funnel_metrics as funnel on o.email = funnel.email
    where o.is_sample_order = 1
        and (funnel.first_product_order_date is null or o.order_date < funnel.first_product_order_date)
    group by 1
),

-- Classify sample order type (business_rules.md section 13)
sample_order_type_classified as (
    select
        email,
        case
            when base_sample_orders > 0 and signature_sample_orders = 0 and craftsman_sample_orders = 0 and silvan_sample_orders = 0 then 'Base Sample Only'
            when signature_sample_orders > 0 and base_sample_orders = 0 and craftsman_sample_orders = 0 and silvan_sample_orders = 0 then 'Signature Sample Only'
            when craftsman_sample_orders > 0 and base_sample_orders = 0 and signature_sample_orders = 0 and silvan_sample_orders = 0 then 'Craftsman Sample Only'
            when silvan_sample_orders > 0 and base_sample_orders = 0 and signature_sample_orders = 0 and craftsman_sample_orders = 0 then 'Silvan Sample Only'
            when base_sample_orders > 0 and signature_sample_orders > 0 and craftsman_sample_orders = 0 and silvan_sample_orders = 0 then 'Base and Signature Sample Only'
            when base_sample_orders > 0 and craftsman_sample_orders > 0 and signature_sample_orders = 0 and silvan_sample_orders = 0 then 'Base and Craftsman Sample Only'
            when signature_sample_orders > 0 and craftsman_sample_orders > 0 and base_sample_orders = 0 and silvan_sample_orders = 0 then 'Signature and Craftsman Sample Only'
            else 'Mixed or Other'
        end as sample_order_type
    from sample_orders_before_purchase
),

-- Final customer funnel table
final as (
    select
        funnel.email,
        funnel.first_order_date,
        funnel.first_sample_order_date,
        funnel.first_sample_order_timestamp,
        funnel.first_product_order_date,
        funnel.first_product_order_timestamp,
        funnel.first_cut_order_date,
        funnel.first_plank_order_date,
        funnel.days_to_order,
        funnel.days_cut_to_order,
        funnel.days_plank_to_order,
        funnel.days_cut_to_plank,
        funnel.converted_within_15d,
        funnel.converted_within_30d,
        funnel.converted_within_60d,
        funnel.converted_within_120d,
        funnel.conversion_ind,
        funnel.has_ever_purchased_product,
        coalesce(sample_type.sample_order_type, 'No Samples') as sample_order_type,

        -- Cohort month (for cohort retention analysis)
        date_trunc(funnel.first_sample_order_date, month) as cohort_month

    from customer_funnel_metrics as funnel
    left join sample_order_type_classified as sample_type
        on funnel.email = sample_type.email
)

select * from final
