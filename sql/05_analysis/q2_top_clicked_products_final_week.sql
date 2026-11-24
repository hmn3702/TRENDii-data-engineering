-- Q2. Top three clicked products for each brand in the final week of the dataset.
-- "Final week" = the last 7 days of data (by generation date), computed from
-- the data rather than hard-coded. Brand comes from dim_product.
CREATE OR REPLACE TABLE ans_q2_top_clicked_products_final_week AS
WITH bounds AS (
    SELECT max(event_date) - INTERVAL 6 DAY AS week_start, max(event_date) AS week_end
    FROM fct_page_views
),
clicks AS (
    SELECT
        k.brand_id,
        k.product_id,
        count(*) AS clicks
    FROM fct_product_clicks k, bounds b
    WHERE k.event_date BETWEEN b.week_start AND b.week_end
    GROUP BY ALL
)
SELECT
    b.week_start::DATE AS week_start,
    b.week_end::DATE   AS week_end,
    br.brand_name,
    r.click_rank,
    p.product_name,
    r.product_id,
    r.clicks
FROM (
    SELECT *, rank() OVER (PARTITION BY brand_id ORDER BY clicks DESC) AS click_rank
    FROM clicks
) r
CROSS JOIN bounds b
JOIN dim_product p USING (product_id)
JOIN dim_brand  br ON br.brand_id = r.brand_id
WHERE r.click_rank <= 3
ORDER BY br.brand_name, r.click_rank, p.product_name;
