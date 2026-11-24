-- dim_publisher: one row per publisher.
CREATE OR REPLACE TABLE dim_publisher AS
SELECT
    publisher_id,
    arg_max(domain, cnt) AS domain          -- most common domain, in case of variants
FROM (
    SELECT publisher_id, domain, count(*) AS cnt
    FROM stg_tagloads
    GROUP BY ALL
)
GROUP BY publisher_id;
