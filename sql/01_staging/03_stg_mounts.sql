-- stg_mounts
-- Grain: one row per (page_view_id, image_id) - an ad unit mounted on an image.
-- A Mounts event bundles every mount of a page load in event_data.mounts[].
CREATE OR REPLACE TABLE stg_mounts AS
SELECT DISTINCT ON (page_view_id, image_id)
    page_view_id,
    event_id,
    event_created_at AS mounted_at,
    event_date,
    publisher_id,
    domain,
    article_url,
    device_id,
    image_id,
    mount_index
FROM (
    SELECT *, m.image_id AS image_id, m.mount_index AS mount_index
    FROM (
        SELECT *, unnest(event_data.mounts) AS m
        FROM stg_events
        WHERE event_name = 'Mounts'
    )
)
WHERE image_id IS NOT NULL
ORDER BY page_view_id, image_id, mount_index;

INSERT INTO audit_load_counts
SELECT 'stg_mounts', 'duplicate mounts (same page view and image) removed',
       (SELECT count(*) FROM (SELECT unnest(event_data.mounts) AS m FROM stg_events WHERE event_name = 'Mounts')
        WHERE m.image_id IS NOT NULL)
       - (SELECT count(*) FROM stg_mounts);
