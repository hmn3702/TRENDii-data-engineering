-- fct_product_impressions
-- Grain: one row per product shown on one image in one page view
--        (page_view_id, image_id, product_id).
--
-- Why de-duplicate? Impression events often list the same product more
-- than once for the same image. In the May 2025 data, 4,744,416 raw product
-- entries collapse to 2,770,303 impressions: 41.6% of raw entries are
-- repeats, and 42.8% of impressions appear more than once (up to 26 times).
-- A product shown on an image is one impression, so repeats are collapsed.
-- The raw count is kept in impression_occurrences.
--
-- brand_id comes from dim_product (trusted), NOT from the event payload.
-- campaign_sk = the campaign version for that brand valid on event_date.
CREATE OR REPLACE TABLE fct_product_impressions AS
WITH dedup AS (
    SELECT
        page_view_id,
        image_id,
        product_id,
        min(event_date)            AS event_date,
        min(impressed_at)          AS impressed_at,
        any_value(publisher_id)    AS publisher_id,
        any_value(article_url)     AS article_url,
        any_value(device_id)       AS device_id,
        min(product_position)      AS product_position,
        any_value(advertised_price) AS advertised_price,
        count(*)                   AS impression_occurrences
    FROM stg_product_impressions
    GROUP BY page_view_id, image_id, product_id
)
SELECT
    d.page_view_id,
    d.image_id,
    d.product_id,
    p.brand_id,
    c.campaign_sk,
    c.campaign_id,
    d.event_date,
    d.impressed_at,
    d.publisher_id,
    d.article_url,
    d.publisher_id || ':' || d.device_id AS user_key,
    d.product_position,
    d.advertised_price,
    d.impression_occurrences
FROM dedup d
LEFT JOIN dim_product  p ON p.product_id = d.product_id
LEFT JOIN dim_campaign c ON c.brand_id = p.brand_id
                        AND d.event_date BETWEEN c.valid_from AND c.valid_to;

INSERT INTO audit_load_counts
SELECT 'fct_product_impressions', 'repeated product entries collapsed into one impression',
       (SELECT count(*) FROM stg_product_impressions)
       - (SELECT count(DISTINCT (page_view_id, image_id, product_id)) FROM fct_product_impressions);
