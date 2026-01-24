{{
    config(
        materialized='table'
    )
}}

/*
    Enhanced Customer Funnel with Household Conversion Tracking

    Purpose:
        Tracks sample-to-product conversion at BOTH email level AND household level.
        Enables identification of conversions where customer uses different emails
        for sample vs product orders but ships to the same address.

    Enhancement (added based on client request):
        - Email-based conversion: Same email orders sample → product
        - Household-based conversion: Same shipping address orders sample → product
        - Captures conversions missed by email-only tracking

    Grain: email (customer level) with household context

    Business Rules: See business_rules.md sections 9, 12, 13
*/

with

orders_classified as (
    select * from {{ ref('int_order_classification') }}
),

order_lines as (
    select * from {{ ref('stg_shopify__order_lines') }}
),

household_ids as (
    select
        order_id,
        email,
        household_id,
        household_key
    from {{ ref('int_household_identification') }}
),

-- Enrich orders with household_id
orders_with_household as (
    select
        o.*,
        h.household_id,
        h.household_key
    from orders_classified o
    left join household_ids h on o.order_id = h.order_id
    where o.email is not null
        and o.email not like '%amazon%'  -- business_rules.md section 18: exclude Amazon marketplace
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

-- EMAIL-BASED: Calculate first order dates per customer (business_rules.md section 9)
email_first_orders as (
    select
        email,

        -- First sample order (sample_quantity > 0 AND product_quantity = 0)
        min(case when is_sample_order = 1 then order_date end) as email_first_sample_order_date,
        min(case when is_sample_order = 1 then processed_at end) as email_first_sample_order_timestamp,

        -- First product order (product_quantity > 0)
        min(case when is_product_order = 1 then order_date end) as email_first_product_order_date,
        min(case when is_product_order = 1 then processed_at end) as email_first_product_order_timestamp,

        -- First cut sample order
        min(case when has_cut_samples = 1 then order_date end) as email_first_cut_order_date,

        -- First plank sample order
        min(case when has_plank_samples = 1 then order_date end) as email_first_plank_order_date,

        -- Overall first order
        min(order_date) as email_first_order_date,

        -- Conversion indicator (did they ever make a product purchase?)
        max(is_product_order) as email_has_ever_purchased_product

    from orders_with_household
    group by 1
),

-- HOUSEHOLD-BASED: Calculate first order dates per household
household_first_orders as (
    select
        household_id,

        -- First sample order at household level
        min(case when is_sample_order = 1 then order_date end) as household_first_sample_order_date,
        min(case when is_sample_order = 1 then processed_at end) as household_first_sample_order_timestamp,

        -- First product order at household level
        min(case when is_product_order = 1 then order_date end) as household_first_product_order_date,
        min(case when is_product_order = 1 then processed_at end) as household_first_product_order_timestamp,

        -- First cut sample order at household level
        min(case when has_cut_samples = 1 then order_date end) as household_first_cut_order_date,

        -- First plank sample order at household level
        min(case when has_plank_samples = 1 then order_date end) as household_first_plank_order_date,

        -- Overall first order at household level
        min(order_date) as household_first_order_date,

        -- Conversion indicator at household level
        max(is_product_order) as household_has_ever_purchased_product,

        -- Track unique emails in this household
        count(distinct email) as household_email_count

    from orders_with_household
    where household_id is not null
    group by 1
),

-- Map each email to their household metrics
email_to_household as (
    select distinct
        email,
        household_id
    from orders_with_household
    where household_id is not null
),

-- EMAIL-BASED: Calculate days to order and conversion windows (business_rules.md section 12)
email_funnel_metrics as (
    select
        *,

        -- Days from sample to product order (email-based)
        date_diff(email_first_product_order_date, email_first_sample_order_date, day) as email_days_to_order,
        date_diff(email_first_product_order_date, email_first_cut_order_date, day) as email_days_cut_to_order,
        date_diff(email_first_product_order_date, email_first_plank_order_date, day) as email_days_plank_to_order,
        date_diff(email_first_plank_order_date, email_first_cut_order_date, day) as email_days_cut_to_plank,

        -- Conversion window flags (email-based)
        case when date_diff(email_first_product_order_date, email_first_sample_order_date, day) <= 15 then 1 else 0 end as email_converted_within_15d,
        case when date_diff(email_first_product_order_date, email_first_sample_order_date, day) <= 30 then 1 else 0 end as email_converted_within_30d,
        case when date_diff(email_first_product_order_date, email_first_sample_order_date, day) <= 60 then 1 else 0 end as email_converted_within_60d,
        case when date_diff(email_first_product_order_date, email_first_sample_order_date, day) <= 120 then 1 else 0 end as email_converted_within_120d,

        -- Conversion indicator (email-based)
        case when email_has_ever_purchased_product = 1 then 1 else 0 end as email_conversion_ind

    from email_first_orders
),

-- HOUSEHOLD-BASED: Calculate days to order and conversion windows
household_funnel_metrics as (
    select
        *,

        -- Days from sample to product order (household-based)
        date_diff(household_first_product_order_date, household_first_sample_order_date, day) as household_days_to_order,
        date_diff(household_first_product_order_date, household_first_cut_order_date, day) as household_days_cut_to_order,
        date_diff(household_first_product_order_date, household_first_plank_order_date, day) as household_days_plank_to_order,
        date_diff(household_first_plank_order_date, household_first_cut_order_date, day) as household_days_cut_to_plank,

        -- Conversion window flags (household-based)
        case when date_diff(household_first_product_order_date, household_first_sample_order_date, day) <= 15 then 1 else 0 end as household_converted_within_15d,
        case when date_diff(household_first_product_order_date, household_first_sample_order_date, day) <= 30 then 1 else 0 end as household_converted_within_30d,
        case when date_diff(household_first_product_order_date, household_first_sample_order_date, day) <= 60 then 1 else 0 end as household_converted_within_60d,
        case when date_diff(household_first_product_order_date, household_first_sample_order_date, day) <= 120 then 1 else 0 end as household_converted_within_120d,

        -- Conversion indicator (household-based)
        case when household_has_ever_purchased_product = 1 then 1 else 0 end as household_conversion_ind

    from household_first_orders
),

-- Determine sample order type based on which categories were sampled
-- This requires looking at all sample orders before first product order (email-based)
sample_orders_before_purchase as (
    select
        o.email,
        sum(case when cat.signature_sample_count > 0 then 1 else 0 end) as signature_sample_orders,
        sum(case when cat.base_sample_count > 0 then 1 else 0 end) as base_sample_orders,
        sum(case when cat.craftsman_sample_count > 0 then 1 else 0 end) as craftsman_sample_orders,
        sum(case when cat.silvan_sample_count > 0 then 1 else 0 end) as silvan_sample_orders

    from orders_with_household as o
    inner join order_categories as cat on o.order_id = cat.order_id
    inner join email_funnel_metrics as funnel on o.email = funnel.email
    where o.is_sample_order = 1
        and (funnel.email_first_product_order_date is null or o.order_date < funnel.email_first_product_order_date)
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

-- Final customer funnel table with both email-based and household-based metrics
final as (
    select
        -- Customer identifier
        email_funnel.email,

        -- Email-based metrics (original logic - kept for backwards compatibility)
        email_funnel.email_first_order_date as first_order_date,
        email_funnel.email_first_sample_order_date as first_sample_order_date,
        email_funnel.email_first_sample_order_timestamp as first_sample_order_timestamp,
        email_funnel.email_first_product_order_date as first_product_order_date,
        email_funnel.email_first_product_order_timestamp as first_product_order_timestamp,
        email_funnel.email_first_cut_order_date as first_cut_order_date,
        email_funnel.email_first_plank_order_date as first_plank_order_date,
        email_funnel.email_days_to_order as days_to_order,
        email_funnel.email_days_cut_to_order as days_cut_to_order,
        email_funnel.email_days_plank_to_order as days_plank_to_order,
        email_funnel.email_days_cut_to_plank as days_cut_to_plank,
        email_funnel.email_converted_within_15d as converted_within_15d,
        email_funnel.email_converted_within_30d as converted_within_30d,
        email_funnel.email_converted_within_60d as converted_within_60d,
        email_funnel.email_converted_within_120d as converted_within_120d,
        email_funnel.email_conversion_ind as conversion_ind,
        email_funnel.email_has_ever_purchased_product as has_ever_purchased_product,

        -- Household identification
        eth.household_id,
        household_funnel.household_email_count,

        -- Household-based metrics (NEW - enhanced conversion tracking)
        household_funnel.household_first_order_date,
        household_funnel.household_first_sample_order_date,
        household_funnel.household_first_sample_order_timestamp,
        household_funnel.household_first_product_order_date,
        household_funnel.household_first_product_order_timestamp,
        household_funnel.household_first_cut_order_date,
        household_funnel.household_first_plank_order_date,
        household_funnel.household_days_to_order,
        household_funnel.household_days_cut_to_order,
        household_funnel.household_days_plank_to_order,
        household_funnel.household_days_cut_to_plank,
        household_funnel.household_converted_within_15d,
        household_funnel.household_converted_within_30d,
        household_funnel.household_converted_within_60d,
        household_funnel.household_converted_within_120d,
        household_funnel.household_conversion_ind,
        household_funnel.household_has_ever_purchased_product,

        -- Hybrid conversion flag: converted at email level OR household level
        case
            when email_funnel.email_conversion_ind = 1
                or household_funnel.household_conversion_ind = 1
            then 1
            else 0
        end as hybrid_conversion_ind,

        -- Sample order type (email-based classification)
        coalesce(sample_type.sample_order_type, 'No Samples') as sample_order_type,

        -- Cohort month (for cohort retention analysis, email-based)
        date_trunc(email_funnel.email_first_sample_order_date, month) as cohort_month

    from email_funnel_metrics as email_funnel
    left join email_to_household eth on email_funnel.email = eth.email
    left join household_funnel_metrics as household_funnel on eth.household_id = household_funnel.household_id
    left join sample_order_type_classified as sample_type on email_funnel.email = sample_type.email
)

select * from final
