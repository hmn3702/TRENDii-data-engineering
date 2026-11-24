-- Q5. How many unique users were advertised to?
-- "Advertised to" = received at least one product impression.
-- "User" = publisher_id + device_id, because device ids are only unique
-- per publisher. distinct_raw_device_ids is shown for transparency.
CREATE OR REPLACE TABLE ans_q5_unique_users_advertised AS
SELECT * FROM (
SELECT
    p.domain,
    count(DISTINCT i.user_key)                         AS users_advertised_to,
    (SELECT count(*) FROM dim_user u WHERE u.publisher_id = p.publisher_id) AS total_users,
    round(100.0 * count(DISTINCT i.user_key)
          / (SELECT count(*) FROM dim_user u WHERE u.publisher_id = p.publisher_id), 2)
                                                       AS pct_of_users
FROM fct_product_impressions i
JOIN dim_publisher p USING (publisher_id)
GROUP BY p.domain, p.publisher_id
UNION ALL
SELECT
    'ALL DOMAINS',
    count(DISTINCT user_key),
    (SELECT count(*) FROM dim_user),
    round(100.0 * count(DISTINCT user_key) / (SELECT count(*) FROM dim_user), 2)
FROM fct_product_impressions
)
ORDER BY domain = 'ALL DOMAINS', domain;
