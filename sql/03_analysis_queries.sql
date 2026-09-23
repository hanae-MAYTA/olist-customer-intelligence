-- =============================================================================
-- 03_analysis_queries.sql — Business questions answered from the RFM views
-- Run after 02_rfm_views.sql.
-- =============================================================================

-- Q1. Size and value of each segment
SELECT
    segment,
    COUNT(*) AS nb_clients,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_clients,
    ROUND(AVG(monetary), 2) AS montant_moyen,
    ROUND(SUM(monetary), 2) AS revenu_total_segment,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenu,
    ROUND(100.0 * AVG(is_repeat_customer::INT), 1) AS pct_clients_fideles
FROM rfm_customer_segments
GROUP BY segment
ORDER BY revenu_total_segment DESC;


-- Q2. How rare is repeat purchasing?
SELECT
    frequency,
    COUNT(*) AS nb_clients,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_clients
FROM rfm_customer_segments
GROUP BY frequency
ORDER BY frequency;


-- Q3. Does the first experience drive repurchase?
-- Repeat rate by review score of the customer's first delivered order.
WITH first_orders AS (
    SELECT DISTINCT ON (c.customer_unique_id)
        c.customer_unique_id,
        o.order_id
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    ORDER BY c.customer_unique_id, o.order_purchase_timestamp
),
first_order_score AS (
    SELECT f.customer_unique_id, ROUND(AVG(r.review_score)) AS first_review_score
    FROM first_orders AS f
    JOIN reviews AS r ON r.order_id = f.order_id
    GROUP BY f.customer_unique_id
)
SELECT
    s.first_review_score,
    COUNT(*) AS nb_clients,
    ROUND(100.0 * AVG(rfm.is_repeat_customer::INT), 2) AS pct_reachat
FROM first_order_score AS s
JOIN rfm_customer_segments AS rfm USING (customer_unique_id)
GROUP BY s.first_review_score
ORDER BY s.first_review_score;


-- Q4. Top 10 states by revenue, with revenue per customer
SELECT
    customer_state,
    SUM(nb_clients) AS nb_clients,
    ROUND(SUM(revenu_total), 2) AS revenu_total,
    ROUND(SUM(revenu_total) / SUM(nb_clients), 2) AS revenu_par_client
FROM segment_geography
GROUP BY customer_state
ORDER BY revenu_total DESC
LIMIT 10;
