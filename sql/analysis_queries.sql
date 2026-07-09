-- ============================================================================
-- Instacart Customer Behavior Case Study — SQL Analysis
--
-- BUSINESS QUESTION:
--   Which customers are at risk of churning, and what products drive repeat purchases?
--
-- APPROACH:
--   Part A — Sanity checks (confirm data before trusting results)
--   Part B — Baseline metrics (customer counts, order volume)
--   Part C — Repeat purchase drivers (department-level reorder analysis)
--   Part D — Churn risk identification (order-gap signals)
--   Part E — Segmentation & retention (RFM, cohorts, cross-category)
--
-- Database: instacart.db
-- ============================================================================


-- =============================================================================
-- PART A: SANITY CHECKS
-- Confirm row counts and reorder rate before building on top of this data.
-- =============================================================================

-- A1. TABLE GRAIN CHECK
-- WHY: If order count ≠ distinct order_ids, every downstream join is suspect.
SELECT
    COUNT(*)                   AS order_rows,
    COUNT(DISTINCT order_id)   AS distinct_orders,
    COUNT(DISTINCT user_id)    AS distinct_users,
    ROUND(AVG(cart_size), 1)   AS avg_cart_size
FROM orders;
-- VALIDATION: order_rows must equal distinct_orders. Reorder rate checked in A2.

-- A2. REORDER RATE BOUNDS CHECK
-- WHY: Rates above 100% indicate a many-to-many join blowup — catch it early.
SELECT
    SUM(cart_size)       AS total_items,
    SUM(reordered_items) AS total_reorders,
    ROUND(100.0 * SUM(reordered_items) / SUM(cart_size), 1) AS reorder_rate_pct
FROM orders;
-- VALIDATION: reorder_rate_pct should be 50–65%. Result: 59.0%


-- =============================================================================
-- PART B: BASELINE METRICS
-- Establish the size and shape of the customer base before segmentation.
-- =============================================================================

-- B1. CUSTOMER BASELINE KPIs
-- WHY: Every later percentage (churn rate, segment share) is relative to this base.
--      Instacart needs to know the denominator before acting on any segment.
WITH user_metrics AS (
    SELECT
        user_id,
        COUNT(*)             AS order_count,
        SUM(cart_size)       AS total_items,
        AVG(cart_size)       AS avg_cart_size,
        SUM(reordered_items) AS total_reorders
    FROM orders
    GROUP BY user_id
)
SELECT
    COUNT(*)                                                    AS total_users,
    ROUND(AVG(order_count), 1)                                  AS avg_orders_per_user,
    ROUND(AVG(total_items), 0)                                  AS avg_items_per_user,
    ROUND(AVG(avg_cart_size), 1)                                AS avg_cart_size,
    ROUND(100.0 * SUM(total_reorders) / SUM(total_items), 1)    AS overall_reorder_rate_pct,
    MIN(order_count)                                            AS min_orders_per_user,
    ROUND(100.0 * SUM(CASE WHEN order_count >= 20 THEN 1 ELSE 0 END) / COUNT(*), 1)
                                                                AS pct_power_users_20plus
FROM user_metrics;
-- VALIDATION: min_orders_per_user = 4 (dataset filters to repeat shoppers only).
--             overall_reorder_rate_pct should match A2 (59.0%).


-- B2. ORDER FREQUENCY DISTRIBUTION
-- WHY: Shows whether the base is dominated by casual or power shoppers —
--      shapes how aggressive retention campaigns should be.
WITH user_orders AS (
    SELECT user_id, COUNT(*) AS order_count
    FROM orders
    GROUP BY user_id
)
SELECT
    CASE
        WHEN order_count BETWEEN 4 AND 6  THEN '4-6 orders'
        WHEN order_count BETWEEN 7 AND 10 THEN '7-10 orders'
        WHEN order_count BETWEEN 11 AND 20 THEN '11-20 orders'
        ELSE '21+ orders'
    END AS frequency_bucket,
    COUNT(*) AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_users
FROM user_orders
GROUP BY frequency_bucket
ORDER BY MIN(order_count);


-- =============================================================================
-- PART C: REPEAT PURCHASE DRIVERS
-- Answers: "What products/departments drive repeat purchases?"
-- =============================================================================

-- C1. REORDER RATE BY DEPARTMENT
-- WHY: Identifies which grocery categories are "habit" purchases vs one-offs.
--      Instacart should prioritize replenishment notifications in high-reorder
--      departments (dairy, produce) rather than low-reorder ones (personal care).
SELECT
    department,
    SUM(items)    AS items_purchased,
    SUM(reorders) AS items_reordered,
    ROUND(100.0 * SUM(reorders) / SUM(items), 1) AS reorder_rate_pct,
    COUNT(DISTINCT user_id) AS unique_buyers
FROM user_departments
GROUP BY department
ORDER BY reorder_rate_pct DESC;
-- VALIDATION: No rate above 100%. Top departments: dairy eggs (~67%), beverages (~65%).
--             Bottom: personal care (~32%), pantry (~35%).


-- C2. DEPARTMENT VOLUME vs LOYALTY
-- WHY: High-volume departments with low reorder rates are growth opportunities;
--      high-volume + high reorder = core retention categories to protect.
SELECT
    department,
    SUM(items) AS total_items,
    ROUND(100.0 * SUM(items) / (SELECT SUM(items) FROM user_departments), 1)
        AS pct_of_all_items,
    ROUND(100.0 * SUM(reorders) / SUM(items), 1) AS reorder_rate_pct
FROM user_departments
GROUP BY department
ORDER BY total_items DESC;
-- VALIDATION: Produce is highest volume (~29% of items) with 65% reorder rate.


-- C3. SHOPPER TIER vs REORDER BEHAVIOR
-- WHY: Tests whether repeat-purchase habit is driven by tenure — if heavy shoppers
--      reorder 2x more than light shoppers, onboarding should push users past
--      the 7-order threshold where reorder rates jump.
WITH user_summary AS (
    SELECT
        user_id,
        COUNT(*)             AS order_count,
        SUM(cart_size)       AS total_items,
        SUM(reordered_items) AS total_reorders
    FROM orders
    GROUP BY user_id
)
SELECT
    CASE
        WHEN order_count BETWEEN 4 AND 6  THEN 'Light (4-6 orders)'
        WHEN order_count BETWEEN 7 AND 15 THEN 'Regular (7-15 orders)'
        ELSE 'Heavy (16+ orders)'
    END AS shopper_tier,
    COUNT(*) AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_base,
    ROUND(AVG(order_count), 1) AS avg_orders,
    ROUND(100.0 * SUM(total_reorders) / SUM(total_items), 1) AS reorder_rate_pct
FROM user_summary
GROUP BY shopper_tier
ORDER BY MIN(order_count);
-- VALIDATION: Light 28.6%, Regular 44.5%, Heavy 67.0% — monotonic increase confirms pattern.


-- =============================================================================
-- PART D: CHURN RISK IDENTIFICATION
-- Answers: "Which customers are at risk of churning?"
-- =============================================================================

-- D1. CHURN RISK — ORDER GAP EXCEEDS 1.5× HISTORICAL AVERAGE
-- WHY: Flags customers whose most recent inter-order gap is 50%+ longer than their
--      personal norm — a leading indicator of churn before they fully disappear.
--      Instacart should trigger a re-engagement email for this cohort.
WITH per_order AS (
    SELECT
        user_id,
        days_since_prior_order AS gap,
        AVG(days_since_prior_order) OVER (PARTITION BY user_id) AS avg_gap,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_number DESC) AS rn,
        COUNT(*) OVER (PARTITION BY user_id) AS gap_count
    FROM orders
    WHERE days_since_prior_order IS NOT NULL
),
latest AS (
    SELECT user_id, gap, avg_gap
    FROM per_order
    WHERE rn = 1 AND gap_count >= 3
)
SELECT
    COUNT(*) AS churn_risk_users,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM latest), 1) AS pct_of_users,
    ROUND(AVG(gap), 1) AS avg_latest_gap_days,
    ROUND(AVG(avg_gap), 1) AS avg_historical_gap_days
FROM latest
WHERE gap >= 1.5 * avg_gap;
-- VALIDATION: pct should be 15–30%. Result: 47,109 users (22.8%).


-- D2. DAYS BETWEEN ORDERS DISTRIBUTION
-- WHY: Contextualizes D1 — shows the typical reorder cadence so the 1.5×
--      threshold can be calibrated (most reorders happen within 7–14 days).
SELECT
    CASE
        WHEN days_since_prior_order <= 7   THEN '0-7 days'
        WHEN days_since_prior_order <= 14  THEN '8-14 days'
        WHEN days_since_prior_order <= 30  THEN '15-30 days'
        WHEN days_since_prior_order <= 60  THEN '31-60 days'
        ELSE '60+ days'
    END AS gap_bucket,
    COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct,
    ROUND(AVG(cart_size), 1) AS avg_cart_size
FROM orders
WHERE days_since_prior_order IS NOT NULL
GROUP BY gap_bucket
ORDER BY MIN(days_since_prior_order);
-- VALIDATION: ~47% of gaps are 0-7 days. Longest tail (60+) is the churn signal.


-- D3. AT-RISK HIGH-ACTIVITY USERS — ACTIONABLE LIST
-- WHY: Combines churn signal (long latest gap) with value (above-average order count)
--      to produce a prioritized list for CRM outreach — not all churn risks are equal.
WITH latest_orders AS (
    SELECT
        user_id,
        order_number,
        days_since_prior_order,
        cart_size,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_number DESC) AS rn
    FROM orders
),
user_history AS (
    SELECT user_id, COUNT(*) AS total_orders, SUM(cart_size) AS total_items
    FROM orders
    GROUP BY user_id
),
threshold AS (
    SELECT AVG(total_orders) AS avg_orders FROM user_history
)
SELECT
    lo.user_id,
    uh.total_orders,
    uh.total_items,
    lo.days_since_prior_order AS latest_gap_days,
    ROUND(lo.days_since_prior_order * 1.0 / NULLIF(
        (SELECT AVG(days_since_prior_order) FROM orders o2
         WHERE o2.user_id = lo.user_id AND o2.days_since_prior_order IS NOT NULL), 0
    ), 2) AS gap_vs_avg_ratio
FROM latest_orders lo
JOIN user_history uh ON lo.user_id = uh.user_id
CROSS JOIN threshold t
WHERE lo.rn = 1
  AND lo.days_since_prior_order >= 30
  AND uh.total_orders >= t.avg_orders
ORDER BY gap_vs_avg_ratio DESC, uh.total_orders DESC
LIMIT 25;
-- VALIDATION: gap_vs_avg_ratio > 1.5 confirms D1 logic on individual users.


-- =============================================================================
-- PART E: SEGMENTATION & RETENTION
-- Deeper cuts for strategic planning — RFM, cohorts, cross-category behavior.
-- =============================================================================

-- E1. RFM SEGMENTATION
-- WHY: Groups users into actionable segments for differentiated marketing —
--      "Lapsed" gets win-back, "Power Shoppers" gets loyalty rewards.
WITH user_rfm AS (
    SELECT
        user_id,
        AVG(days_since_prior_order) AS avg_days_between_orders,
        COUNT(*)                      AS frequency,
        SUM(cart_size)                AS monetary_items
    FROM orders
    WHERE days_since_prior_order IS NOT NULL
    GROUP BY user_id
),
rfm_scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY avg_days_between_orders ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency DESC)              AS f_score,
        NTILE(5) OVER (ORDER BY monetary_items DESC)         AS m_score
    FROM user_rfm
)
SELECT
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Power Shoppers'
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Regulars'
        WHEN r_score <= 2 AND f_score >= 3                   THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2                   THEN 'Lapsed'
        ELSE 'Emerging Loyalists'
    END AS rfm_segment,
    COUNT(*) AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_users,
    ROUND(AVG(frequency), 1) AS avg_orders,
    ROUND(AVG(monetary_items), 0) AS avg_items
FROM rfm_scored
GROUP BY rfm_segment
ORDER BY users DESC;


-- E2. ORDER-NUMBER COHORT RETENTION
-- WHY: Shows where in the customer lifecycle drop-off happens — if retention
--      falls sharply after order 5, target incentives at orders 4-5.
WITH user_max_order AS (
    SELECT user_id, MAX(order_number) AS max_order_number
    FROM orders
    GROUP BY user_id
)
SELECT
    milestone.n AS order_milestone,
    COUNT(*) AS users_reached,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM user_max_order), 1) AS pct_of_all_users
FROM user_max_order
JOIN (
    SELECT 4 AS n UNION ALL SELECT 5 UNION ALL SELECT 7
    UNION ALL SELECT 10 UNION ALL SELECT 15 UNION ALL SELECT 20
) milestone ON user_max_order.max_order_number >= milestone.n
GROUP BY milestone.n
ORDER BY milestone.n;
-- VALIDATION: 100% reach order 4, 88% reach order 5, 54% reach order 10.


-- E3. CROSS-DEPARTMENT PURCHASE BEHAVIOR
-- WHY: Tests whether breadth of shopping predicts loyalty — if users buying from
--      more departments reorder more, Instacart should encourage cross-category discovery.
WITH user_dept_summary AS (
    SELECT
        user_id,
        COUNT(DISTINCT department) AS departments_shopped,
        SUM(items)                 AS total_items,
        SUM(reorders)              AS total_reorders
    FROM user_departments
    GROUP BY user_id
),
user_orders AS (
    SELECT user_id, COUNT(*) AS order_count
    FROM orders
    GROUP BY user_id
)
SELECT
    ud.departments_shopped,
    COUNT(*) AS users,
    ROUND(AVG(uo.order_count), 1) AS avg_orders,
    ROUND(100.0 * SUM(ud.total_reorders) / SUM(ud.total_items), 1) AS reorder_rate_pct
FROM user_dept_summary ud
JOIN user_orders uo ON ud.user_id = uo.user_id
GROUP BY ud.departments_shopped
ORDER BY ud.departments_shopped;
-- VALIDATION: Users shopping 1 dept reorder at ~79%; 10+ depts at ~45% —
--             specialists reorder more than explorers.
