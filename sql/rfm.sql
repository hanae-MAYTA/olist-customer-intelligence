WITH valid_orders AS (

    SELECT
        o.order_id,
        c.customer_unique_id,
        o.order_purchase_timestamp::TIMESTAMP AS order_purchase_timestamp
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'

),

order_value AS (

    SELECT
        order_id,
        SUM(payment_value) AS total_value
    FROM payments
    WHERE payment_value > 0
    GROUP BY order_id

),

customer_orders AS (

    SELECT
        vo.customer_unique_id,
        vo.order_id,
        vo.order_purchase_timestamp,
        ov.total_value
    FROM valid_orders vo
    JOIN order_value ov
        ON ov.order_id = vo.order_id

),

rfm_base AS (

    SELECT
        customer_unique_id,
        MAX(order_purchase_timestamp) AS last_purchase,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(total_value) AS monetary
    FROM customer_orders
    GROUP BY customer_unique_id

),

reference_date AS (

    SELECT
        MAX(order_purchase_timestamp) AS max_date
    FROM valid_orders

),

rfm_values AS (

    SELECT
        r.customer_unique_id,
        (rd.max_date::DATE - r.last_purchase::DATE) AS recency,
        r.frequency,
        ROUND(r.monetary::NUMERIC, 2) AS monetary

    FROM rfm_base r
    CROSS JOIN reference_date rd

),

rfm_scores AS (

    SELECT
        customer_unique_id,
        recency,
        frequency,
        monetary,

        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,

        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 3
            WHEN frequency BETWEEN 3 AND 4 THEN 4
            WHEN frequency >= 5 THEN 5
        END AS f_score,

        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score

    FROM rfm_values

),

rfm_final AS (

    SELECT
        customer_unique_id,
        recency,
        frequency,
        monetary,
        r_score,
        f_score,
        m_score,
        (r_score + f_score + m_score) AS rfm_total,
        CONCAT(r_score, f_score, m_score) AS rfm_code

    FROM rfm_scores

)

SELECT
    *,
    CASE
        -- Champions : récent, achète souvent, dépense beaucoup
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
            THEN 'Champions'

        -- Loyal Customers : achète souvent, peu importe le montant
        WHEN f_score >= 4 AND r_score >= 3
            THEN 'Loyal Customers'

        -- Big One-Time Spenders : un seul achat mais récent et gros montant
        -- (profil fréquent chez Olist vu le peu de réachat)
        WHEN f_score = 1 AND m_score >= 4 AND r_score >= 3
            THEN 'Big One-Time Spenders'

        -- New Customers : achat très récent, encore peu d'historique
        WHEN r_score >= 4 AND f_score <= 2
            THEN 'New Customers'

        -- At Risk : étaient de bons clients (fréquence ou montant élevé) mais n'achètent plus depuis longtemps
        WHEN r_score <= 2 AND (f_score >= 3 OR m_score >= 4)
            THEN 'At Risk'

        -- Lost : faible sur toutes les dimensions
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2
            THEN 'Lost'

        -- tout le reste : clients moyens, pas encore assez distincts
        ELSE 'Need Attention'
    END AS segment

FROM rfm_final
ORDER BY rfm_total DESC;







WITH valid_orders AS (
    SELECT o.order_id, c.customer_unique_id, o.order_purchase_timestamp::TIMESTAMP AS order_purchase_timestamp
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
order_value AS (
    SELECT order_id, SUM(payment_value) AS total_value
    FROM payments WHERE payment_value > 0
    GROUP BY order_id
),
customer_orders AS (
    SELECT vo.customer_unique_id, vo.order_id, vo.order_purchase_timestamp, ov.total_value
    FROM valid_orders vo JOIN order_value ov ON ov.order_id = vo.order_id
),
rfm_base AS (
    SELECT customer_unique_id, MAX(order_purchase_timestamp) AS last_purchase,
           COUNT(DISTINCT order_id) AS frequency, SUM(total_value) AS monetary
    FROM customer_orders GROUP BY customer_unique_id
),
reference_date AS (
    SELECT MAX(order_purchase_timestamp) AS max_date FROM valid_orders
),
rfm_values AS (
    SELECT r.customer_unique_id, (rd.max_date::DATE - r.last_purchase::DATE) AS recency,
           r.frequency, ROUND(r.monetary::NUMERIC, 2) AS monetary
    FROM rfm_base r CROSS JOIN reference_date rd
),
rfm_scores AS (
    SELECT customer_unique_id, recency, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 3
            WHEN frequency BETWEEN 3 AND 4 THEN 4
            WHEN frequency >= 5 THEN 5
        END AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_values
),
rfm_final AS (
    SELECT customer_unique_id, recency, frequency, monetary, r_score, f_score, m_score,
           (r_score + f_score + m_score) AS rfm_total,
           CONCAT(r_score, f_score, m_score) AS rfm_code
    FROM rfm_scores
),
rfm_segmented AS (
    SELECT *,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN f_score >= 4 AND r_score >= 3 THEN 'Loyal Customers'
            WHEN f_score = 1 AND m_score >= 4 AND r_score >= 3 THEN 'Big One-Time Spenders'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
            WHEN r_score <= 2 AND (f_score >= 3 OR m_score >= 4) THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Lost'
            ELSE 'Need Attention'
        END AS segment
    FROM rfm_final
)
SELECT
    segment,
    COUNT(*) AS nb_clients,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_clients,
    ROUND(AVG(monetary), 2) AS montant_moyen,
    ROUND(SUM(monetary), 2) AS revenu_total_segment
FROM rfm_segmented
GROUP BY segment
ORDER BY nb_clients DESC;