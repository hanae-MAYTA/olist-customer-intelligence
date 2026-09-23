-- =============================================================================
-- 02_rfm_views.sql — RFM scoring, segmentation and analysis views
--
-- Scope      : delivered orders only (a cancelled order is not a purchase).
-- Customer   : customers.customer_unique_id (customer_id changes at every order).
-- Monetary   : sum of payments, i.e. products + freight, in BRL.
-- Reference  : recency is measured from the last delivered purchase in the
--              dataset (2018-08-29), not from today.
-- Output column names are kept stable because the Power BI report uses them.
-- =============================================================================

CREATE OR REPLACE VIEW rfm_customer_segments AS
WITH delivered_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id,
        c.customer_state,
        o.order_purchase_timestamp
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),

order_value AS (
    SELECT order_id, SUM(payment_value) AS order_value
    FROM payments
    GROUP BY order_id
),

rfm_values AS (
    SELECT
        d.customer_unique_id,
        -- state of the most recent order (39 customers moved between states)
        (ARRAY_AGG(d.customer_state ORDER BY d.order_purchase_timestamp DESC))[1] AS customer_state,
        (SELECT MAX(order_purchase_timestamp) FROM delivered_orders)::DATE
            - MAX(d.order_purchase_timestamp)::DATE AS recency,
        COUNT(*) AS frequency,
        SUM(v.order_value) AS monetary
    FROM delivered_orders AS d
    JOIN order_value AS v ON v.order_id = d.order_id
    GROUP BY d.customer_unique_id
),

rfm_scores AS (
    SELECT
        *,
        -- Quintile scores (1 = worst, 5 = best). CUME_DIST gives tied values
        -- the same score, unlike NTILE which splits ties arbitrarily.
        CEIL(5 * CUME_DIST() OVER (ORDER BY recency DESC))::INT AS r_score,
        -- ~97% of customers bought once, so quintiles are meaningless for F:
        -- use business thresholds instead.
        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 3
            WHEN frequency <= 4 THEN 4
            ELSE 5
        END AS f_score,
        CEIL(5 * CUME_DIST() OVER (ORDER BY monetary))::INT AS m_score
    FROM rfm_values
)

SELECT
    customer_unique_id,
    customer_state,
    recency,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    r_score + f_score + m_score AS rfm_total,
    CONCAT(r_score, f_score, m_score) AS rfm_code,
    -- Segments are built on Recency x Monetary, the two dimensions with real variance.
    CASE
        WHEN r_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND m_score >= 3 THEN 'Potential Loyalists'
        WHEN r_score >= 4 AND m_score <= 2 THEN 'New Customers'
        WHEN r_score <= 2 AND m_score >= 4 THEN 'At Risk'
        WHEN r_score <= 2 AND m_score <= 2 THEN 'Lost'
        ELSE 'Need Attention'
    END AS segment,
    -- Loyalty is tracked separately from the segment.
    frequency >= 2 AS is_repeat_customer
FROM rfm_scores;


-- Revenue (item price, freight excluded) by segment and product category
CREATE OR REPLACE VIEW segment_category_analysis AS
SELECT
    rfm.segment,
    p.product_category_name_english AS category,
    COUNT(DISTINCT oi.order_id) AS nb_commandes,
    SUM(oi.price) AS revenu_categorie
FROM rfm_customer_segments AS rfm
JOIN customers AS c    ON c.customer_unique_id = rfm.customer_unique_id
JOIN orders AS o       ON o.customer_id = c.customer_id
JOIN order_items AS oi ON oi.order_id = o.order_id
JOIN products AS p     ON p.product_id = oi.product_id
WHERE o.order_status = 'delivered'
GROUP BY rfm.segment, p.product_category_name_english;


-- Review scores by segment (delivered orders only, consistent with the RFM scope)
CREATE OR REPLACE VIEW segment_satisfaction AS
SELECT
    rfm.segment,
    ROUND(AVG(r.review_score), 2) AS note_moyenne,
    COUNT(*) AS nb_avis,
    ROUND(100.0 * AVG((r.review_score <= 2)::INT), 1) AS pct_avis_negatifs
FROM rfm_customer_segments AS rfm
JOIN customers AS c ON c.customer_unique_id = rfm.customer_unique_id
JOIN orders AS o    ON o.customer_id = c.customer_id
JOIN reviews AS r   ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY rfm.segment;


-- Customers and revenue by segment and state. One state per customer, so
-- revenue is not duplicated for customers with several customer_id.
CREATE OR REPLACE VIEW segment_geography AS
SELECT
    segment,
    customer_state,
    COUNT(*) AS nb_clients,
    SUM(monetary) AS revenu_total
FROM rfm_customer_segments
GROUP BY segment, customer_state;
