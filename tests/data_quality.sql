-- Data-quality tests.
-- Each test is one query that returns the number of FAILING rows.
-- Format: "-- test: <name> | <severity: error|warn>" then a single query ending with ";".
-- error -> pipeline exits with failure; warn -> logged only.

-- test: stg_events has rows | error
SELECT CASE WHEN count(*) = 0 THEN 1 ELSE 0 END FROM stg_events;

-- test: rejected events (bad/missing fields) | warn
SELECT count(*) FROM stg_events_rejected;

-- test: event_id unique in stg_events | error
SELECT count(*) - count(DISTINCT event_id) FROM stg_events;

-- test: one tagload per page view | error
SELECT count(*) - count(DISTINCT page_view_id) FROM fct_page_views;

-- test: mounts without a tagload | warn
SELECT count(*) FROM fct_mounts m
WHERE NOT EXISTS (SELECT 1 FROM fct_page_views p WHERE p.page_view_id = m.page_view_id);

-- test: impressions on images that were never mounted | warn
SELECT count(*) FROM fct_product_impressions i
WHERE NOT EXISTS (SELECT 1 FROM fct_mounts m
                  WHERE m.page_view_id = i.page_view_id AND m.image_id = i.image_id);

-- test: clicks without a matching impression | warn
SELECT count(*) FROM fct_product_clicks k
WHERE NOT EXISTS (SELECT 1 FROM fct_product_impressions i
                  WHERE i.page_view_id = k.page_view_id AND i.image_id = k.image_id
                    AND i.product_id = k.product_id);

-- test: impression product missing from dim_product | error
SELECT count(*) FROM fct_product_impressions WHERE brand_id IS NULL;

-- test: click product missing from dim_product | error
SELECT count(*) FROM fct_product_clicks WHERE brand_id IS NULL;

-- test: impression with no campaign valid on its date | warn
SELECT count(*) FROM fct_product_impressions WHERE campaign_sk IS NULL;

-- test: impression matched to more than one campaign version (fan-out) | error
SELECT count(*) FROM (
    SELECT page_view_id, image_id, product_id FROM fct_product_impressions
    GROUP BY ALL HAVING count(*) > 1
);

-- test: click matched to more than one campaign version (fan-out) | error
SELECT count(*) - count(DISTINCT click_id) FROM fct_product_clicks;

-- test: overlapping SCD2 campaign versions | error
SELECT count(*) FROM dim_campaign a JOIN dim_campaign b
  ON a.campaign_id = b.campaign_id AND a.campaign_sk < b.campaign_sk
 AND a.valid_from <= b.valid_to AND b.valid_from <= a.valid_to;

-- test: campaign with more than one current record | error
SELECT count(*) FROM (SELECT campaign_id FROM dim_campaign WHERE current_record
                      GROUP BY 1 HAVING count(*) > 1);

-- test: campaign billing type inferred (blank product_type in source) | warn
SELECT count(*) FROM dim_campaign WHERE is_billing_type_inferred;

-- test: event brand_id disagrees with dim_product (impressions) | warn
SELECT count(*) FROM stg_product_impressions s JOIN dim_product p USING (product_id)
WHERE s.event_brand_id <> p.brand_id;

-- test: product_id unique in dim_product | error
SELECT count(*) - count(DISTINCT product_id) FROM dim_product;

-- test: product with negative or null price | warn
SELECT count(*) FROM dim_product WHERE rrp IS NULL OR rrp < 0 OR sale_price < 0;
