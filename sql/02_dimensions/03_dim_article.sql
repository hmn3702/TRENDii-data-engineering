-- dim_article: one row per article. The brief says the URL is the article's
-- unique identifier, so article_url is the natural key.
CREATE OR REPLACE TABLE dim_article AS
SELECT
    article_url,
    any_value(publisher_id)   AS publisher_id,
    any_value(domain)         AS domain,
    min(event_date)           AS first_seen_date,
    max(event_date)           AS last_seen_date
FROM stg_tagloads
GROUP BY article_url;
