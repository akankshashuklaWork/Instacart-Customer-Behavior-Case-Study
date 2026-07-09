-- ============================================================================
-- STEP 0: SCHEMA EXPLORATION & DATA VALIDATION
-- Run this BEFORE analysis queries. Verify grain, joins, and nulls — don't assume.
-- Database: instacart.db
-- ============================================================================


-- 0.1 ROW COUNTS — confirm each table loaded and grain is as expected
SELECT 'orders'           AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL
SELECT 'user_departments', COUNT(*) FROM user_departments
UNION ALL
SELECT 'products',         COUNT(*) FROM products;


-- 0.2 SAMPLE ROWS — inspect column values and formats
SELECT * FROM orders LIMIT 5;
SELECT * FROM user_departments LIMIT 5;
SELECT * FROM products LIMIT 5;


-- 0.3 KEY UNIQUENESS — orders should be one row per order_id
SELECT
    COUNT(*)              AS total_rows,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT user_id)  AS distinct_users
FROM orders;
-- Expected: total_rows = distinct_orders (3,421,083)


-- 0.4 NULL CHECK — first order per user has no days_since_prior_order (expected)
SELECT
    COUNT(*) AS orders_with_null_gap,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders), 1) AS pct
FROM orders
WHERE days_since_prior_order IS NULL;
-- Expected: ~6% (one null gap per user's first order)


-- 0.5 JOIN INTEGRITY — every user in user_departments exists in orders
SELECT COUNT(*) AS orphan_user_dept_rows
FROM user_departments ud
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = ud.user_id
);
-- Expected: 0


-- 0.6 REORDER RATE SANITY — must be between 0% and 100%
SELECT
    ROUND(100.0 * SUM(reordered_items) / SUM(cart_size), 1) AS overall_reorder_rate_pct
FROM orders;
-- Expected: ~59%. If >100%, you have a join blowup or double-counting.


-- 0.7 MIN ORDERS PER USER — dataset only includes users with repeat history
SELECT MIN(order_count) AS min_orders_per_user
FROM (SELECT user_id, COUNT(*) AS order_count FROM orders GROUP BY user_id);
-- Expected: 4 (competition dataset filters to active repeat shoppers)
