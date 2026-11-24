-- Data-quality tests.
-- Each test is one query that returns the number of FAILING rows.
-- Format: "-- test: <name> | <severity: error|warn>" then a single query ending with ";".
-- error -> pipeline exits with failure and answers are NOT exported;
-- warn  -> logged only (used for things that are handled, but worth seeing).

-- test: stg_events has rows | error
SELECT CASE WHEN count(*) = 0 THEN 1 ELSE 0 END FROM stg_events;

-- test: rejected events (bad/missing fields) | warn
SELECT count(*) FROM stg_events_rejected;

-- De-duplication counts (from audit_load_counts). These cannot fail the
-- run - duplicates are handled - but they show how many were removed.
-- A missing count returns NULL, which the runner treats as an error.

-- test: re-delivered events removed (duplicate event_id) | warn
SELECT (SELECT value FROM audit_load_counts WHERE metric = 're-delivered events removed (duplicate event_id)');

-- test: extra TagLoaded events for the same page view removed | warn
SELECT (SELECT value FROM audit_load_counts WHERE metric = 'extra TagLoaded events for the same page view removed');

-- test: duplicate mounts removed | warn
SELECT (SELECT value FROM audit_load_counts WHERE metric = 'duplicate mounts (same page view and image) removed');

-- test: clicks without a click_id dropped | warn
SELECT (SELECT value FROM audit_load_counts WHERE metric = 'clicks without a click_id dropped');

-- test: duplicate clicks removed (same click_id) | warn
SELECT (SELECT value FROM audit_load_counts WHERE metric = 'duplicate clicks removed (same click_id)');

-- test: repeated product entries collapsed into one impression | warn
SELECT (SELECT value FROM audit_load_counts WHERE metric = 'repeated product entries collapsed into one impression');

-- test: more than one impression event for the same page view and image | warn
-- Impressions are de-duplicated by page view x image x product, so counts stay
-- correct either way. This only flags that repeats are no longer all inside a
-- single event (the docs state that they are, for the May 2025 data).
SELECT count(*) - count(DISTINCT (page_view_id, event_data.image_id))
FROM stg_events
WHERE event_name = 'ProductImpressions';

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

-- test: overlapping campaign versions for the same brand | error
-- Events are linked to campaigns through the product's brand, so two
-- campaign rows (same or different campaign) valid for one brand on the
-- same day would double-count every impression and click of that brand.
SELECT count(*) FROM dim_campaign a JOIN dim_campaign b
  ON a.brand_id = b.brand_id AND a.campaign_sk < b.campaign_sk
 AND a.valid_from <= b.valid_to AND b.valid_from <= a.valid_to;

-- test: campaign with more than one current record | error
SELECT count(*) FROM (SELECT campaign_id FROM dim_campaign WHERE current_record
                      GROUP BY 1 HAVING count(*) > 1);

-- test: campaign billing type inferred (blank product_type in source) | warn
SELECT count(*) FROM dim_campaign WHERE is_billing_type_inferred;

-- Evidence for trusting dim_product over the event payload: the product
-- name and URL in the events should match dim_product for the same
-- product_id, while the event brand_id does not.

-- test: event brand_id disagrees with dim_product (impressions) | warn
SELECT count(*) FROM stg_product_impressions s JOIN dim_product p USING (product_id)
WHERE s.event_brand_id <> p.brand_id;

-- test: event brand_id disagrees with dim_product (clicks) | warn
SELECT count(*) FROM stg_product_clicks s JOIN dim_product p USING (product_id)
WHERE s.event_brand_id <> p.brand_id;

-- test: event product name or URL disagrees with dim_product | warn
SELECT (SELECT count(*) FROM stg_product_impressions s JOIN dim_product p USING (product_id)
        WHERE s.event_product_name IS DISTINCT FROM p.product_name
           OR s.event_product_url  IS DISTINCT FROM p.product_url)
     + (SELECT count(*) FROM stg_product_clicks s JOIN dim_product p USING (product_id)
        WHERE s.event_product_name IS DISTINCT FROM p.product_name
           OR s.event_product_url  IS DISTINCT FROM p.product_url);

-- test: advertised price differs from dim_product RRP | warn
SELECT (SELECT count(*) FROM stg_product_impressions s JOIN dim_product p USING (product_id)
        WHERE s.advertised_price IS DISTINCT FROM p.rrp)
     + (SELECT count(*) FROM stg_product_clicks s JOIN dim_product p USING (product_id)
        WHERE s.advertised_price IS DISTINCT FROM p.rrp);

-- test: product_id unique in dim_product | error
SELECT count(*) - count(DISTINCT product_id) FROM dim_product;

-- test: product with negative or null price | warn
SELECT count(*) FROM dim_product WHERE rrp IS NULL OR rrp < 0 OR sale_price < 0;
