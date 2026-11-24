-- agg_daily_product_performance
-- Grain: one row per (event_date, product). Impressions, clicks, CTR and
-- estimated revenue for CPC / CPM campaigns (CPA needs sales data, which
-- is not provided, so CPA revenue is left NULL).
CREATE OR REPLACE TABLE agg_daily_product_performance AS
WITH imp AS (
    SELECT event_date, product_id, campaign_sk, count(*) AS impressions
    FROM fct_product_impressions GROUP BY ALL
),
clk AS (
    SELECT event_date, product_id, campaign_sk, count(*) AS clicks
    FROM fct_product_clicks GROUP BY ALL
)
SELECT
    coalesce(imp.event_date, clk.event_date)    AS event_date,
    coalesce(imp.product_id, clk.product_id)    AS product_id,
    p.product_name,
    p.brand_id,
    p.brand_name,
    c.campaign_id,
    c.campaign_name,
    c.billing_type,
    coalesce(imp.impressions, 0)                AS impressions,
    coalesce(clk.clicks, 0)                     AS clicks,
    round(coalesce(clk.clicks, 0) / nullif(imp.impressions, 0), 6) AS click_through_rate,
    CASE c.billing_type
        WHEN 'CPC' THEN coalesce(clk.clicks, 0) * c.cpc_rate
        WHEN 'CPM' THEN coalesce(imp.impressions, 0) / 1000.0 * c.cpm_rate
    END                                          AS estimated_revenue
FROM imp
FULL OUTER JOIN clk
  ON imp.event_date = clk.event_date
 AND imp.product_id = clk.product_id
 AND imp.campaign_sk IS NOT DISTINCT FROM clk.campaign_sk
LEFT JOIN dim_product  p ON p.product_id  = coalesce(imp.product_id, clk.product_id)
LEFT JOIN dim_campaign c ON c.campaign_sk = coalesce(imp.campaign_sk, clk.campaign_sk);
