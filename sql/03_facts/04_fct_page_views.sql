-- fct_page_views
-- Grain: one row per page view / tagload (page_view_id).
-- An accumulating "funnel" fact: tagload -> mount -> impression -> click.
CREATE OR REPLACE TABLE fct_page_views AS
WITH m AS (
    SELECT page_view_id, count(*) AS mounted_images
    FROM fct_mounts GROUP BY 1
),
i AS (
    SELECT page_view_id,
           count(DISTINCT image_id) AS impressed_images,
           count(*)                 AS product_impressions
    FROM fct_product_impressions GROUP BY 1
),
k AS (
    SELECT page_view_id, count(*) AS clicks
    FROM fct_product_clicks GROUP BY 1
)
SELECT
    t.page_view_id,
    t.event_date,
    t.tagloaded_at,
    t.publisher_id,
    t.article_url,
    t.publisher_id || ':' || t.device_id   AS user_key,
    coalesce(m.mounted_images, 0)          AS mounted_images,
    coalesce(i.impressed_images, 0)        AS impressed_images,
    coalesce(i.product_impressions, 0)     AS product_impressions,
    coalesce(k.clicks, 0)                  AS clicks,
    m.page_view_id IS NOT NULL             AS has_mount,
    i.page_view_id IS NOT NULL             AS has_impression,
    k.page_view_id IS NOT NULL             AS has_click
FROM stg_tagloads t
LEFT JOIN m USING (page_view_id)
LEFT JOIN i USING (page_view_id)
LEFT JOIN k USING (page_view_id);
