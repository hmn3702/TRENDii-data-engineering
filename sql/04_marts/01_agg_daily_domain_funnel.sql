-- agg_daily_domain_funnel
-- Grain: one row per (event_date, publisher). Ready-made KPIs for
-- dashboards: traffic, mount rate, impressions, clicks, CTR.
CREATE OR REPLACE TABLE agg_daily_domain_funnel AS
SELECT
    f.event_date,
    f.publisher_id,
    p.domain,
    count(*)                                         AS tagloads,
    count(DISTINCT f.user_key)                       AS users,
    count(*) FILTER (WHERE f.has_mount)              AS page_views_with_mount,
    sum(f.mounted_images)::BIGINT                    AS mounted_images,
    count(*) FILTER (WHERE f.has_impression)         AS page_views_with_impression,
    sum(f.product_impressions)::BIGINT               AS product_impressions,
    sum(f.clicks)::BIGINT                            AS clicks,
    round(count(*) FILTER (WHERE f.has_mount) / count(*), 4)          AS mount_rate,
    round(sum(f.clicks) / nullif(sum(f.product_impressions), 0), 6)   AS click_through_rate
FROM fct_page_views f
JOIN dim_publisher p USING (publisher_id)
GROUP BY ALL;
