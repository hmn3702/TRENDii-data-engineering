-- stg_product_clicks
-- Grain: one row per click (click_id). Re-delivered clicks are dropped.
CREATE OR REPLACE TABLE stg_product_clicks AS
SELECT DISTINCT ON (click_id)
    event_data.click_id      AS click_id,
    page_view_id,
    event_id,
    event_created_at         AS clicked_at,
    event_date,
    publisher_id,
    domain,
    article_url,
    device_id,
    event_data.image_id      AS image_id,
    event_data.product_id    AS product_id,
    event_data.brand_id      AS event_brand_id,
    event_data.product_name  AS event_product_name,
    event_data.product_price AS advertised_price,
    event_data.product_url   AS event_product_url
FROM stg_events
WHERE event_name = 'ProductClick'
  AND event_data.click_id IS NOT NULL
ORDER BY click_id, event_created_at;
