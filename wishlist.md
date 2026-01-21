Think of this as a **semantic contract** an LLM (or data team) could reliably reason over.

---

# 📊 Company Data & Insight Wish List (LLM-Optimized)

## 0. Global Conventions (Applies Everywhere)

**Core Entities**

* customer_id
* order_id
* sample_order_id
* product_order_id
* sku
* product_color
* product_category
* product_line
* supplier_id
* warehouse_id
* region
* channel
* campaign / coupon_code

**Common Time Grains**

* event_time (timestamp)
* date (day)
* week
* month
* cohort_month (e.g., first_sample_order_month)

**Metric Types**

* volume (count, quantity)
* rate (%, probability)
* velocity (per day/week)
* cost ($)
* margin ($, %)
* prediction (score, likelihood)
* classification (segment, cohort)

---

## 1. Executive & Financial Intelligence

### 1.1 Company Health & Financial Performance

**Revenue & Margin**

* Net revenue, gross margin (GM), contribution margin (CM)
* Breakdown by:

  * store
  * channel
  * category
  * product line
  * SKU
* Grain: date × dimension

**Unit Economics**

* Order-level profitability
* SKU-level profitability
* Grain: order_id, sku

**Cash & Cost Structure**

* Cash conversion cycle (DIO, DSO, DPO)
* OPEX visibility:

  * labor
  * warehouse
  * fulfillment
* Cash flow forecasting
* Grain: month

---

### 1.2 Profitability Drivers

**SKU Profit Waterfall**

* Price
* Discounts
* Shipping
* Returns
* COGS
* Net margin
* Grain: sku, order_id

**Cost to Serve**

* Cost per customer
* Cost per order
* Cost per region/channel
* Grain: order_id, customer_id

---

## 2. Inventory, Supply Chain & Forecasting

### 2.1 Inventory Intelligence

**Inventory Position**

* Inventory on hand (weeks, months)
* Inventory aging
* Stockout probability
* Safety stock levels
* Grain: sku, warehouse_id, date

**Replenishment**

* Recommended reorder quantities
* Recommended reorder dates
* Lead time–aware forecasting
* Grain: sku, supplier_id

**Supplier Performance**

* Lead time accuracy
* Reliability score
* Quality scorecards
* Defect rates
* Grain: supplier_id, sku

**True Landed Cost**

* COGS
* Freight
* Handling
* Storage
* Grain: sku

---

### 2.2 Demand & Labor Forecasting

**Demand Forecasting**

* Predictive demand by SKU/category
* Inputs:

  * historical sales
  * marketing spend
  * promotions
  * seasonality
  * macro trends
* Forecast accuracy reporting (weekly, monthly)
* Grain: sku, week

**Labor & Capacity Forecasting**

* Warehouse labor needs
* Units shipped per labor hour
* Capacity constraints
* Grain: warehouse_id, date

---

## 3. Marketing Attribution & Growth Efficiency

### 3.1 Attribution & Spend Efficiency

* CAC by channel, influencer, coupon, region
* ROAS by channel and cohort
* Attribution across:

  * ads → sample → purchase
* Grain: channel, cohort_month

---

### 3.2 Sample Program Intelligence

**Sample Conversion Analysis**

* Conversion rates by:

  * sample code
  * quantity
  * product mix
  * region
* Time from sample → purchase
* Zero-sample purchase rates
* Grain: customer_id, sample_order_id

**Remarketing Optimization**

* Optimal remarketing windows by cohort
* Channel impact on conversion speed

---

### 3.3 Sample Recommendation Engine (Decision Support)

* “Customers like this also sampled”
* Optimized sample bundles
* Sample AOV → downstream revenue impact
* Sample channel attribution
* Grain: cohort_id

---

## 4. Customer Intelligence & Lifetime Value

### 4.1 Customer Segmentation

* Segmentation by:

  * behavior
  * geography
  * product mix
  * acquisition channel
  * price sensitivity
* New vs returning dynamics
* Grain: customer_id

---

### 4.2 Lifetime Value (LTV)

* Revenue LTV
* Contribution margin LTV
* LTV by:

  * category
  * sample code
  * acquisition channel
  * region
* 3 / 6 / 12-month projections
* Grain: customer_id, cohort_month

---

### 4.3 Behavioral Journeys

* Sample → purchase → install flows
* Dropoffs & friction points
* Early signals of high LTV
* What high-LTV customers do differently
* Grain: customer_id, event_sequence

---

## 5. Returns, Cancellations & Risk

### 5.1 Returns & Defects

* Return rates by:

  * SKU
  * color
  * lot number
* Defect trend detection
* Grain: sku, lot_number

**Text Mining**

* Return reasons
* CS themes
* Review sentiment

---

### 5.2 Cancellation & Risk Modeling

* Cancellation likelihood by:

  * customer type
  * behavior
  * region
  * timing
* Refund prediction models
* Checkout risk score
* Grain: order_id

---

## 6. Operations & Fulfillment Performance

### 6.1 Warehouse Performance

* Pick errors
* Damage rates
* Rework rates
* Units shipped per labor hour
* Grain: warehouse_id, date

---

### 6.2 Carrier Performance

* On-time delivery %
* Cost per order / pallet
* Damage rates
* Delivery issues by region & SKU
* Alerts for fulfillment delays
* Grain: carrier_id, region, date

---

### 6.3 Order Cycle Time

* Order → pick
* Pick → stage
* Stage → ship
* Ship → delivery
* Grain: order_id

---

## 7. Pricing & Promotion Intelligence

* Price elasticity by SKU/category
* Impact of price changes on:

  * conversion
  * demand velocity
  * sample orders
* Margin optimization models
* Competitive benchmarking (if available)
* Discount effectiveness (conversion vs margin)
* Grain: sku, date

---

## 8. Predictive Customer Experience (CX)

### 8.1 Early Warning Signals

* Predictors of low NPS / CSAT:

  * delays
  * risky regions
  * site behavior
  * prior issues
* At-risk customer alerts
* Issue clustering
* Grain: customer_id, order_id

---

### 8.2 Voice of Customer (VOC)

* Sentiment trends across:

  * reviews
  * CS tickets
  * surveys
* CSAT/NPS driver analysis
* Grain: sku, region, date

---

## 9. Fraud & High-Risk Orders

* Pattern detection for:

  * fraud
  * disputes
  * cancellations
* Risk scoring at checkout
* Grain: order_id

---

## 10. Website & Digital Product Analytics

### 10.1 Funnel & Conversion

* Homepage → PLP → PDP → cart → checkout
* Funnel dropoff analysis
* Grain: session_id, date

---

### 10.2 UX & Behavior Signals

* Page load times
* Heatmaps
* Scroll depth
* Session replays
* Rage clicks
* Zero-result searches
* Visualizer engagement
* Grain: session_id, event_type

---

### 10.3 Device & Region Patterns

* Desktop vs mobile
* Time-of-day behavior
* Region-specific friction
* Grain: device, region, date

---

## 11. Executive Digital Scorecards (Chronological View)

### 11.1 Prospect → Sample Optimization

* PDP/PLP → sample funnel
* Intent signals
* Propensity-to-sample scoring
* Cohorted conversion rates

---

### 11.2 Sample → Full Box Conversion

* Sample SKU → product SKU mapping
* Time-to-purchase curves
* Conversion probability modeling
* Automated alerts for drops

---

### 11.3 Executive Performance Scorecard

* Monthly funnel performance
* Best/worst PDPs
* Sample payback windows
* Accessory attach contribution
* CX drivers impacting revenue

---

### 11.4 Accessories & Attach Rate Intelligence

* Attach rate by:

  * SKU
  * device
  * traffic source
* Price elasticity vs attach probability
* Predictive bundle recommendations

---

### 11.5 Email & SMS Performance

* LTV by acquisition source
* Opt-in rates by placement
* Deliverability health
* Creative performance
* Churn prediction
* Grain: subscriber_id, campaign_id

---

## 12. Data Architecture & Foundations

* Unified metric definitions
* Single source of truth
* Automated ELT pipelines
* Data quality monitoring & alerts
* Access control & governance
* Dashboard-ready semantic models

---

## 13. Existing Metrics (Reference Layer)

> These are **already implemented** elsehwere so we know we can implement them here with the daata we have

* Executive sales, revenue, orders, traffic, conversion
* Sample funnel & conversion metrics
* Product performance (category, color, SKU)
* Coupon & attribution reporting
* Order quality & operational stats
* Customer lifetime & recency metrics

---
