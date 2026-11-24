-- stg_tagloads
-- Grain: one row per page view (a TagLoaded event = one "tagload").
-- If a page view ever had more than one TagLoaded we keep the first.
CREATE OR REPLACE TABLE stg_tagloads AS
SELECT * EXCLUDE (rn)
FROM (
    SELECT
        page_view_id,
        event_id,
        event_created_at AS tagloaded_at,
        event_date,
        publisher_id,
        domain,
        article_url,
        device_id,
        user_agent,
        row_number() OVER (PARTITION BY page_view_id ORDER BY event_created_at) AS rn
    FROM stg_events
    WHERE event_name = 'TagLoaded'
)
WHERE rn = 1;
