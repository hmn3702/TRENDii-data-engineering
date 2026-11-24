-- Q1. Top five articles by traffic (tagloads) per domain.
-- RANK() keeps ties, so a domain can show more than 5 rows if articles tie.
CREATE OR REPLACE TABLE ans_q1_top_articles_by_domain AS
SELECT domain, traffic_rank, article_url, tagloads
FROM (
    SELECT
        p.domain,
        f.article_url,
        count(*) AS tagloads,
        rank() OVER (PARTITION BY p.domain ORDER BY count(*) DESC) AS traffic_rank
    FROM fct_page_views f
    JOIN dim_publisher p USING (publisher_id)
    GROUP BY p.domain, f.article_url
)
WHERE traffic_rank <= 5
ORDER BY domain, traffic_rank, article_url;
