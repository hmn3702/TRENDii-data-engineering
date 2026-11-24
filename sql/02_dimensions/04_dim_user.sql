-- dim_user: one row per user as TRENDii can see them.
-- device_id (did) is only unique *per publisher*, so the user key is
-- publisher_id + device_id. The same human on two publisher sites is two
-- users here - there is no cross-publisher identifier in the data.
CREATE OR REPLACE TABLE dim_user AS
SELECT
    publisher_id || ':' || device_id                 AS user_key,
    publisher_id,
    device_id,
    min(event_date)                                  AS first_seen_date,
    max(event_date)                                  AS last_seen_date,
    count(*)                                         AS page_views,
    arg_max(user_agent, tagloaded_at)                AS latest_user_agent,
    CASE
        WHEN arg_max(user_agent, tagloaded_at) ILIKE '%ipad%'
          OR arg_max(user_agent, tagloaded_at) ILIKE '%tablet%'                 THEN 'tablet'
        WHEN arg_max(user_agent, tagloaded_at) ILIKE '%mobile%'
          OR arg_max(user_agent, tagloaded_at) ILIKE '%iphone%'
          OR arg_max(user_agent, tagloaded_at) ILIKE '%android%'                THEN 'mobile'
        ELSE 'desktop'
    END                                              AS device_type
FROM stg_tagloads
GROUP BY publisher_id, device_id;
