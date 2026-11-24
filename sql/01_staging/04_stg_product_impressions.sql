-- stg_product_impressions
-- Grain: one row per product entry inside a ProductImpressions event
--        (i.e. NOT de-duplicated - raw exploded data).
-- product_position = position of the product in the products[] array (1-based).
-- The brand_id / price / name carried in the event are kept with an
-- "event_" prefix because they disagree with dim_product for most rows.
CREATE OR REPLACE TABLE stg_product_impressions AS
SELECT
    page_view_id,
    event_id,
    event_created_at AS impressed_at,
    event_date,
    publisher_id,
    domain,
    article_url,
    device_id,
    image_id,
    product_position,
    p.product_id    AS product_id,
    p.brand_id      AS event_brand_id,
    p.product_name  AS event_product_name,
    p.product_price AS advertised_price,
    p.product_url   AS event_product_url
FROM (
    SELECT
        *,
        event_data.image_id AS image_id,
        unnest(event_data.products)                          AS p,
        generate_subscripts(event_data.products, 1)          AS product_position
    FROM stg_events
    WHERE event_name = 'ProductImpressions'
)
WHERE p.product_id IS NOT NULL;
