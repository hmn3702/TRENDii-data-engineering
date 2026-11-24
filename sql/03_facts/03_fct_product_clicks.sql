-- fct_product_clicks
-- Grain: one row per click (click_id).
-- brand / campaign resolved the same way as fct_product_impressions.
CREATE OR REPLACE TABLE fct_product_clicks AS
SELECT
    k.click_id,
    k.page_view_id,
    k.image_id,
    k.product_id,
    p.brand_id,
    c.campaign_sk,
    c.campaign_id,
    k.event_date,
    k.clicked_at,
    k.publisher_id,
    k.article_url,
    k.publisher_id || ':' || k.device_id AS user_key,
    k.advertised_price,
    CASE WHEN c.billing_type = 'CPC' THEN c.cpc_rate END AS cpc_revenue
FROM stg_product_clicks k
LEFT JOIN dim_product  p ON p.product_id = k.product_id
LEFT JOIN dim_campaign c ON c.brand_id = p.brand_id
                        AND k.event_date BETWEEN c.valid_from AND c.valid_to;
