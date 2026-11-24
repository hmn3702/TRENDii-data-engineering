-- Q3. Which product got the most impressions for each campaign?
-- Impression = product shown on an image in a page view (de-duplicated grain).
-- All SCD versions of a campaign are combined (grouped by campaign_id).
-- raw_impression_occurrences shows the count before de-duplication.
CREATE OR REPLACE TABLE ans_q3_top_product_per_campaign AS
WITH per_product AS (
    SELECT
        i.campaign_id,
        i.product_id,
        count(*)                      AS impressions,
        sum(i.impression_occurrences) AS raw_impression_occurrences
    FROM fct_product_impressions i
    WHERE i.campaign_id IS NOT NULL
    GROUP BY ALL
),
campaigns AS (
    SELECT campaign_id, arg_max(campaign_name, valid_to) AS campaign_name,
           arg_max(billing_type, valid_to) AS billing_type
    FROM dim_campaign GROUP BY campaign_id
)
SELECT
    c.campaign_name,
    c.campaign_id,
    c.billing_type,
    p.product_name,
    r.product_id,
    r.impressions,
    r.raw_impression_occurrences
FROM (
    SELECT *, rank() OVER (PARTITION BY campaign_id ORDER BY impressions DESC) AS rnk
    FROM per_product
) r
JOIN campaigns  c USING (campaign_id)
JOIN dim_product p USING (product_id)
WHERE r.rnk = 1
ORDER BY c.campaign_name;
