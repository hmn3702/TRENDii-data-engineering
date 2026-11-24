-- fct_mounts
-- Grain: one row per ad unit mounted on an image in a page view
--        (page_view_id, image_id).
CREATE OR REPLACE TABLE fct_mounts AS
SELECT
    page_view_id,
    image_id,
    mount_index,
    event_date,
    mounted_at,
    publisher_id,
    article_url,
    publisher_id || ':' || device_id AS user_key
FROM stg_mounts;
