-- Q4. Mount rate per domain = mounts / tagloads.
-- "Mounts" is read as Mounts events (= page views where ad units mounted),
-- giving a 0-100% rate. mounted_images_per_tagload is the alternative
-- reading (individual image mounts / tagloads) and is shown alongside.
CREATE OR REPLACE TABLE ans_q4_mount_rate_by_domain AS
SELECT * FROM (
SELECT
    p.domain,
    count(*)                                              AS tagloads,
    count(*) FILTER (WHERE f.has_mount)                   AS mounts,
    round(100.0 * count(*) FILTER (WHERE f.has_mount) / count(*), 2) AS mount_rate_pct,
    sum(f.mounted_images)::BIGINT                         AS mounted_images,
    round(sum(f.mounted_images) / count(*), 2)            AS mounted_images_per_tagload
FROM fct_page_views f
JOIN dim_publisher p USING (publisher_id)
GROUP BY p.domain
UNION ALL
SELECT
    'ALL DOMAINS',
    count(*),
    count(*) FILTER (WHERE has_mount),
    round(100.0 * count(*) FILTER (WHERE has_mount) / count(*), 2),
    sum(mounted_images)::BIGINT,
    round(sum(mounted_images) / count(*), 2)
FROM fct_page_views
)
ORDER BY domain = 'ALL DOMAINS', domain;
