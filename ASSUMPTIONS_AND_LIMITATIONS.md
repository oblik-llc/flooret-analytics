# Assumptions and Limitations - Flooret Analytics Phase 2

**Purpose:** Document all assumptions, workarounds, and limitations for YELLOW and RED metrics in the Flooret Analytics dbt project.

**Status Date:** 2026-01-20

---

## Document Structure

This document categorizes metrics by implementation status:
- ✅ **GREEN**: Fully implemented with complete data
- 🟡 **YELLOW**: Implemented with assumptions/workarounds (documented below)
- 🔴 **RED**: Cannot implement due to missing data sources (client action required)

---

## YELLOW Metrics (Implemented with Assumptions)

### 1. Unit Economics (`fct_unit_economics`)

**Status:** 🟡 Partial Implementation

**What's Available:**
- Revenue (gross, net after discounts)
- Shipping costs (from Freightview)
- Ad spend allocation (for new customers)
- Discounts and refunds
- Contribution margin BEFORE COGS

**Critical Limitation:**
❌ **COGS (Cost of Goods Sold) data is NOT AVAILABLE**

**Missing Cost Components:**
- Product COGS (raw materials, manufacturing, freight-in)
- Warehouse labor costs (pick, pack, QC, receiving)
- Payment processing fees (~2.9% + $0.30 per transaction)
- Packaging materials
- Returns processing labor
- Customer service costs per order

**Calculated Metric:**
`Contribution Margin Before COGS = Revenue - Shipping Cost - Allocated Ad Spend`

This is NOT true profitability. It shows "how much is left after variable costs" but does NOT account for the cost of the product itself.

**Business Questions This CAN Answer:**
- Which orders have the highest variable cost burden?
- What is CAC payback period (time to recover ad spend from customer)?
- How do shipping costs vary by region?
- What is the impact of discounts on economics?

**Business Questions This CANNOT Answer:**
- Is this order profitable?
- Which SKUs are profitable vs loss leaders?
- What is our break-even volume?
- Should we raise or lower prices?
- What is our true gross margin?

**Client Action Required:**
1. Where is COGS tracked? (ERP system? Spreadsheet? NetSuite?)
2. Is COGS tracked at SKU level or blended?
3. Does COGS include freight-in and handling costs?
4. Can we get historical COGS data synced to BigQuery?

---

### 2. Demand Forecasting (`int_demand_forecast_prep`)

**Status:** 🟡 Partial Implementation

**What's Available:**
- Historical sales by SKU (quantity, revenue, order count)
- Calendar features (day of week, month, seasonality indicators)
- Lagged metrics (7d, 14d, 28d)
- Rolling averages (7d, 28d, 90d)
- Marketing spend as demand driver
- Trend features (days since first sale, sales velocity)

**Critical Limitations:**
❌ **No external demand signals**
❌ **No inventory constraints modeled**
❌ **No promotional calendar**

**Missing Demand Drivers:**
- Housing starts / construction activity (macro indicator for flooring)
- Weather patterns (cold winters → more indoor renovations)
- Competitor pricing changes
- Supply chain disruptions
- Inventory stockouts (sales data doesn't show lost sales)
- Promotional calendar (planned sales events, marketing campaigns)

**Assumptions:**
1. Historical patterns predict future demand (may not capture market shifts)
2. No supply constraints (assumes all demand was met)
3. Marketing spend is the only external demand driver available
4. Seasonality is stable year-over-year

**Use Cases:**
- Trend analysis and seasonality detection
- Short-term forecasting (7-30 days ahead)
- Identifying demand volatility by SKU

**Not Suitable For:**
- Long-term forecasting (6+ months) without macro indicators
- Forecasting during market disruptions or new product launches
- Inventory optimization without stockout data

**Client Action Required:**
1. Do you track promotional calendars or planned marketing campaigns?
2. Are there known external demand drivers (construction activity, housing market)?
3. Do you have historical stockout data (lost sales)?
4. What forecasting horizon is most important (days, weeks, months)?

---

### 3. Marketing Attribution (`dim_attribution`, `int_ad_spend_attribution`)

**Status:** 🟡 Not Yet Implemented - Needs Investigation

**What's Available:**
- GA4 events with session data
- Facebook Ads URL report with UTM parameters
- Google Ads campaign performance
- Shopify orders with customer emails
- Ad spend by channel/campaign/day

**Critical Limitations:**
❌ **UTM parameters not linked to Shopify orders**
❌ **No clear join key between GA4 sessions and Shopify orders**

**Missing Attribution Data:**
- UTM parameters in Shopify order attributes
- GA4 client_id or user_id in Shopify orders
- Shopify order_id or order_name in GA4 purchase events (we have transaction_id but need validation)
- First-touch and last-touch tracking across sessions

**Assumptions:**
1. GA4 `transaction_id` field matches Shopify order identifiers (needs validation)
2. Attribution window: 7-day click, 1-day view (standard, but not validated)
3. Email is the only common identifier between systems (no device fingerprinting)

**What Can Be Built (with assumptions):**
- Last-touch attribution: Link GA4 purchase events → transaction_id → Shopify orders
- Channel-level attribution: Aggregate conversions by utm_source
- Campaign performance: ROAS by utm_campaign

**What Cannot Be Built:**
- Multi-touch attribution (no session history linked to orders)
- First-touch attribution (no way to identify first interaction)
- Attribution across devices (email-based only)
- View-through attribution (no impression tracking linked to orders)

**Client Action Required:**
1. Validate: Does GA4 `transaction_id` match Shopify order identifiers?
2. Are UTM parameters captured in Shopify order attributes or customer tags?
3. What attribution model do you want? (first-touch, last-touch, linear, time-decay)
4. What attribution window should be used? (7-day? 14-day? 30-day?)
5. Do you use any attribution tools already (Segment, Rockerbox, Northbeam)?

---

### 4. Website Funnel Analysis (`fct_ga4_funnel`)

**Status:** 🟡 Partial Implementation

**What's Available:**
- Session-level funnel tracking (Homepage → PLP → PDP → Cart → Checkout → Purchase)
- Conversion rates at each stage
- Dropoff rates and counts
- Session duration and engagement metrics

**Critical Limitations:**
❌ **Page types inferred from URL patterns** (not explicit GA4 page_type dimension)
❌ **No device-level breakdown** (desktop vs mobile not included)
❌ **No A/B test tracking**

**Assumptions:**
1. Page type classification from URLs:
   - `/products/*` = product_detail
   - `/collections/*` = product_list
   - `/cart` = cart
   - `/checkout` = checkout
2. Any PDP view = funnel stage reached (doesn't require specific SKU)
3. Session is the unit of analysis (not user journey across sessions)

**Use Cases:**
- Daily/weekly funnel performance tracking
- Dropoff rate identification
- Conversion rate optimization
- Time-series funnel analysis

**Not Suitable For:**
- Device-specific optimization (need to add device dimension)
- A/B test impact measurement (need test variant tracking)
- Cross-session journey analysis (need user-level funnel)

**Client Action Required:**
1. Are there explicit GA4 custom dimensions for page_type?
2. Should we add device (desktop/mobile/tablet) breakdown?
3. Are A/B tests tracked in GA4? (custom dimensions or events)
4. Do you want user-level journeys or session-level is sufficient?

---

### 5. Customer Service Insights (`fct_cs_insights`)

**Status:** 🟡 Not Implemented - Blocked by Schema Gap

**What's Available:**
- Gladly conversations table (no column schema documented)
- Gladly messages table (no column schema documented)
- Gladly agents table (no column schema documented)

**Critical Limitations:**
❌ **No column definitions in source YAML files**
❌ **No conversation topic/category fields known**
❌ **No refund reason codes documented**
❌ **No NLP models for text analysis**

**Missing Data:**
- Conversation timestamps (created, first_response, resolved)
- Conversation status (open, closed, waiting)
- Conversation topic/category
- Customer email (to link to orders)
- Agent information
- Channel (email, chat, phone, SMS)
- Refund reason codes (structured or free text?)

**What Could Be Built (with schema):**
- Conversation volume by date/channel
- Average response time and resolution time
- Agent performance metrics
- Topic frequency analysis (if categorized)
- Correlation between CS contact and returns/refunds

**What Cannot Be Built:**
- Sentiment analysis (requires NLP or survey data)
- Root cause analysis (requires structured refund reasons)
- NPS/CSAT driver analysis (requires survey data)
- Predictive models for at-risk customers

**Client Action Required:**
1. Provide column schema for Gladly tables (conversations, messages, agents)
2. Are conversation topics/categories tracked in Gladly?
3. Are refund reasons structured or free text?
4. Do you run NPS/CSAT surveys? (Delighted? Qualtrics? Typeform?)
5. Do you have product reviews? (Shopify Reviews? Yotpo? Okendo?)

---

## RED Metrics (Cannot Implement - Missing Data Sources)

### 1. Profitability Metrics

**Blocked Metrics:**
- Gross margin (GM) by SKU/order/customer
- Contribution margin (CM) by SKU/order/customer
- Net margin by SKU/order/customer
- SKU-level profit waterfall
- Margin optimization analysis

**Missing Data:**
- COGS (Cost of Goods Sold) by SKU
- Warehouse labor costs
- Payment processing fees
- Packaging material costs

**Impact:**
Cannot answer critical business questions like:
- Which products are profitable?
- What is our break-even revenue?
- Should we discontinue low-margin SKUs?
- What price increases would optimize margin?

**Client Action Required:**
1. Where is COGS data stored? (ERP, spreadsheet, accounting system)
2. Is COGS tracked at SKU level or product category level?
3. Can COGS be synced to BigQuery via Fivetran or API?
4. What is the update frequency for COGS (real-time, daily, monthly)?

---

### 2. Inventory & Supply Chain

**Blocked Metrics:**
- Inventory aging analysis
- Stockout frequency by SKU
- Reorder point recommendations
- Supplier lead time reliability
- True landed cost by SKU
- Inventory turnover ratio

**Missing Data:**
- Historical inventory levels (Shopify has current only)
- Supplier purchase orders
- Supplier lead times
- Inbound freight costs (freight-in)
- Warehouse receiving timestamps
- Lot numbers and batch tracking

**Impact:**
Cannot answer critical questions like:
- Do we have slow-moving inventory?
- What is optimal reorder quantity by SKU?
- Which suppliers are most reliable?
- What is true landed cost vs selling price?

**Client Action Required:**
1. Do you use a WMS (Warehouse Management System) or just Shopify?
2. Where are purchase orders tracked? (NetSuite? QuickBooks? Spreadsheet?)
3. Are supplier lead times documented?
4. Is lot number tracking available for quality/defect analysis?
5. Can inventory snapshot data be captured daily?

---

### 3. Warehouse Operations

**Blocked Metrics:**
- Pick accuracy rate
- Pack time per order
- Damage rates by carrier vs warehouse
- Units per labor hour
- Capacity utilization
- Rework and defect rates

**Missing Data:**
- WMS event logs (pick, pack, stage, ship)
- Labor hours by activity
- Warehouse damage incidents
- Rework/QC events
- Facility capacity data

**Impact:**
Cannot answer operational questions like:
- Are we staffed appropriately?
- Which activities are bottlenecks?
- Is damage caused by warehouse or carrier?
- What is our operational efficiency trend?

**Client Action Required:**
1. Do you use a WMS with event-level tracking?
2. Is warehouse labor tracked (hours by activity)?
3. Are warehouse damage incidents logged?
4. Do you have facility capacity constraints to model?

---

### 4. Returns & Quality Defects

**Blocked Metrics:**
- Return rate by lot number
- Defect trends over time
- Root cause analysis by manufacturing batch
- Supplier quality scorecards

**Missing Data:**
- Lot number tracking on line items
- Manufacturing batch information
- Structured defect reason codes

**Impact:**
Cannot answer quality questions like:
- Is this a bad batch or systemic issue?
- Which supplier has quality problems?
- Are defect rates improving or worsening?

**Client Action Required:**
1. Are lot numbers tracked on orders or in warehouse?
2. Can lot numbers be added to Shopify line item metadata?
3. Are defect types categorized in Gladly or elsewhere?

---

### 5. Customer Feedback & Satisfaction

**Blocked Metrics:**
- NPS score trends
- CSAT driver analysis
- Product review sentiment
- Feedback themes (NLP on reviews)

**Missing Data:**
- NPS/CSAT survey responses
- Product reviews (Yotpo? Shopify Reviews?)
- Survey metadata (response rate, timing)

**Impact:**
Cannot answer customer satisfaction questions like:
- What drives high NPS vs low NPS?
- Which product attributes get best/worst reviews?
- Is customer satisfaction improving?

**Client Action Required:**
1. Do you run NPS or CSAT surveys? What platform?
2. Where are product reviews stored?
3. Can survey and review data be synced to BigQuery?

---

### 6. Competitive Intelligence

**Blocked Metrics:**
- Price comparison vs competitors
- Share of voice
- Competitive product launches

**Missing Data:**
- Competitor pricing data
- Market share data
- Competitive intelligence feeds

**Impact:**
Cannot answer competitive questions like:
- Are we priced competitively?
- Are we losing market share?

**Client Action Required:**
1. Do you track competitor pricing? (manual or tool?)
2. Do you have market share data? (industry reports?)
3. Is competitive intelligence a priority for analytics?

---

### 7. Payment & Fraud

**Blocked Metrics:**
- Payment failure rates
- Chargeback rates
- Fraud risk scoring
- Payment gateway performance

**Missing Data:**
- Stripe/PayPal transaction details
- Payment failure reasons
- Fraud flags and risk scores
- Chargeback data

**Impact:**
Cannot answer payment questions like:
- Why are payments failing?
- What is our chargeback rate trend?
- Are fraudulent orders being caught?

**Client Action Required:**
1. Which payment gateways do you use? (Stripe? PayPal? Shopify Payments?)
2. Can payment data be synced to BigQuery?
3. Do you use fraud detection tools? (Signifyd? Riskified?)

---

## Summary Statistics

### Implementation Status

| Status | Count | Percentage | Description |
|--------|-------|------------|-------------|
| ✅ GREEN | 35 | 60% | Fully implemented with complete data |
| 🟡 YELLOW | 18 | 30% | Implemented with assumptions (documented above) |
| 🔴 RED | 6 | 10% | Blocked by missing data sources |

### Critical Client Actions Required (Priority Order)

**Priority 1 (Blocks Profitability Analysis):**
1. **COGS Data Source** - Where is cost data tracked? Can it be synced to BigQuery?
2. **Payment Processing Fees** - Stripe/PayPal transaction data access
3. **Warehouse Labor Costs** - How to allocate warehouse costs to orders?

**Priority 2 (Blocks Inventory Optimization):**
4. **Purchase Orders** - Where are supplier POs tracked?
5. **Inventory Snapshots** - Can we capture daily inventory levels?
6. **Supplier Lead Times** - Where is supplier performance documented?

**Priority 3 (Blocks Customer Insights):**
7. **Gladly Column Schema** - Provide full schema for conversations/messages tables
8. **NPS/CSAT Survey Data** - What survey tool is used? Can data be synced?
9. **Product Review Data** - Where are reviews stored?

**Priority 4 (Improves Attribution):**
10. **UTM Parameter Validation** - Confirm GA4 transaction_id matches Shopify order identifiers
11. **Attribution Strategy** - Define preferred attribution model and window

---

## Recommendations

### Short-Term (Immediate)
1. **Validate GREEN metrics** - Run dbt models and verify accuracy against existing reports
2. **Prioritize COGS integration** - This unblocks 80% of profitability analysis
3. **Document Gladly schema** - Quick win to enable CS insights

### Medium-Term (1-3 months)
4. **Integrate payment gateway data** - Enables payment failure and fraud analysis
5. **Capture inventory snapshots** - Build historical inventory dataset for forecasting
6. **Implement survey data sync** - Enables NPS/CSAT driver analysis

### Long-Term (3-6 months)
7. **WMS integration** - Enables warehouse operations analytics
8. **Supplier PO system integration** - Enables supply chain analytics
9. **Competitive intelligence feeds** - Enables market positioning analysis

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-20 | 1.0 | Initial documentation (Sprint 4) |

---

## Contact & Questions

For questions about assumptions or to provide missing data:
1. Review this document with stakeholders
2. Prioritize data source integrations based on business impact
3. Update `_sources.yml` files as new data becomes available
4. Re-run dbt models to incorporate new data sources
