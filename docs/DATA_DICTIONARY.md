# Data dictionary

Every table the pipeline builds in `warehouse/trendii.duckdb`, with the meaning of each column. Column names and types are taken from the built database. Row counts are for the provided May 2025 data.

**How to read it:** *Grain* = what one row represents. *Key* = the column(s) that make a row unique. *FK -> table* = the column joins to that table.

**Layers:** Facts (what happened) and Dimensions (descriptions) form the star schema; Marts are ready-made daily summaries; Analysis outputs answer the five questions; Staging is the cleaned raw data everything else is built from. See [DATA_MODEL.md](DATA_MODEL.md) for the diagram.

## Contents

- **Facts:** [`fct_page_views`](#fct_page_views), [`fct_mounts`](#fct_mounts), [`fct_product_impressions`](#fct_product_impressions), [`fct_product_clicks`](#fct_product_clicks)
- **Dimensions:** [`dim_date`](#dim_date), [`dim_publisher`](#dim_publisher), [`dim_article`](#dim_article), [`dim_user`](#dim_user), [`dim_brand`](#dim_brand), [`dim_product`](#dim_product), [`dim_campaign`](#dim_campaign)
- **Marts:** [`agg_daily_domain_funnel`](#agg_daily_domain_funnel), [`agg_daily_product_performance`](#agg_daily_product_performance)
- **Analysis outputs:** [`ans_q1_top_articles_by_domain`](#ans_q1_top_articles_by_domain), [`ans_q2_top_clicked_products_final_week`](#ans_q2_top_clicked_products_final_week), [`ans_q3_top_product_per_campaign`](#ans_q3_top_product_per_campaign), [`ans_q4_mount_rate_by_domain`](#ans_q4_mount_rate_by_domain), [`ans_q5_unique_users_advertised`](#ans_q5_unique_users_advertised)
- **Staging:** [`audit_load_counts`](#audit_load_counts), [`stg_events`](#stg_events), [`stg_events_rejected`](#stg_events_rejected), [`stg_tagloads`](#stg_tagloads), [`stg_mounts`](#stg_mounts), [`stg_product_impressions`](#stg_product_impressions), [`stg_product_clicks`](#stg_product_clicks), [`stg_products`](#stg_products), [`stg_campaigns`](#stg_campaigns)

## Facts

### fct_page_views

Funnel summary of each page load: did ads mount, were products shown, were they clicked.

- **Grain:** One row per page view (tagload)
- **Key:** `page_view_id`
- **Rows:** 164,663

| Column | Type | Description |
|---|---|---|
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `tagloaded_at` | TIMESTAMP | When the TagLoaded event was ingested. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `user_key` | VARCHAR | User key = `publisher_id:device_id`. FK -> dim_user. |
| `mounted_images` | BIGINT | Number of images that had an ad unit mounted. |
| `impressed_images` | BIGINT | Number of distinct images that showed products. |
| `product_impressions` | BIGINT | Number of product impressions on this page view (de-duplicated). |
| `clicks` | BIGINT | Number of clicks on this page view. |
| `has_mount` | BOOLEAN | TRUE if at least one ad unit mounted. |
| `has_impression` | BOOLEAN | TRUE if at least one product was shown. |
| `has_click` | BOOLEAN | TRUE if at least one product was clicked. |

### fct_mounts

Every image that received a TRENDii ad unit.

- **Grain:** One row per ad unit mounted on an image in a page view
- **Key:** `page_view_id, image_id`
- **Rows:** 1,629,474

| Column | Type | Description |
|---|---|---|
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `image_id` | VARCHAR | ID of the image an ad unit was placed on. Unique within a page view. |
| `mount_index` | BIGINT | Position of the mount on the page; 0 = highest. |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `mounted_at` | TIMESTAMP | When the Mounts event was ingested. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `user_key` | VARCHAR | User key = `publisher_id:device_id`. FK -> dim_user. |

### fct_product_impressions

Product impressions, de-duplicated, enriched with the true brand and the campaign version valid that day.

- **Grain:** One row per product shown on one image in one page view
- **Key:** `page_view_id, image_id, product_id`
- **Rows:** 2,770,303

| Column | Type | Description |
|---|---|---|
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `image_id` | VARCHAR | ID of the image an ad unit was placed on. Unique within a page view. |
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `brand_id` | VARCHAR | Brand ID. In facts and marts this comes from dim_product (trusted), not from the event. FK -> dim_brand. |
| `campaign_sk` | VARCHAR | Surrogate key of the campaign *version* valid on event_date. FK -> dim_campaign. NULL if no campaign was running. |
| `campaign_id` | VARCHAR | Business ID of the campaign (same across SCD versions). |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `impressed_at` | TIMESTAMP | When the ProductImpressions event was ingested (earliest, if repeated). |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `user_key` | VARCHAR | User key = `publisher_id:device_id`. FK -> dim_user. |
| `product_position` | BIGINT | Position of the product in the impression's products[] list (1 = first). |
| `advertised_price` | DOUBLE | Product price shown in the ad at the time of the event (`product_price` in the event). |
| `impression_occurrences` | BIGINT | How many times this product appeared in the raw event before de-duplication. 1 for 57% of impressions, 2 for 31%, up to 26. |

### fct_product_clicks

Product clicks enriched with true brand and campaign version.

- **Grain:** One row per click
- **Key:** `click_id`
- **Rows:** 1,402

| Column | Type | Description |
|---|---|---|
| `click_id` | VARCHAR | Unique ID of a click. |
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `image_id` | VARCHAR | ID of the image an ad unit was placed on. Unique within a page view. |
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `brand_id` | VARCHAR | Brand ID. In facts and marts this comes from dim_product (trusted), not from the event. FK -> dim_brand. |
| `campaign_sk` | VARCHAR | Surrogate key of the campaign *version* valid on event_date. FK -> dim_campaign. NULL if no campaign was running. |
| `campaign_id` | VARCHAR | Business ID of the campaign (same across SCD versions). |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `clicked_at` | TIMESTAMP | When the ProductClick event was ingested. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `user_key` | VARCHAR | User key = `publisher_id:device_id`. FK -> dim_user. |
| `advertised_price` | DOUBLE | Product price shown in the ad at the time of the event (`product_price` in the event). |
| `cpc_revenue` | DOUBLE | Revenue earned from this click if the campaign is CPC (= cpc_rate valid that day), else NULL. |


## Dimensions

### dim_date

Calendar table.

- **Grain:** One row per day in the data
- **Key:** `date_day`
- **Rows:** 31

| Column | Type | Description |
|---|---|---|
| `date_day` | DATE | Calendar date. |
| `year` | BIGINT | Year. |
| `month` | BIGINT | Month number (1-12). |
| `day_of_month` | BIGINT | Day of month. |
| `iso_day_of_week` | BIGINT | Day of week, 1 = Monday ... 7 = Sunday. |
| `day_name` | VARCHAR | Day name (Monday...). |
| `week_start_monday` | DATE | Monday of the week this day belongs to. |
| `is_weekend` | BOOLEAN | TRUE for Saturday / Sunday. |

### dim_publisher

Publisher websites.

- **Grain:** One row per publisher
- **Key:** `publisher_id`
- **Rows:** 3

| Column | Type | Description |
|---|---|---|
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |

### dim_article

Articles that loaded the TRENDii tag.

- **Grain:** One row per article
- **Key:** `article_url`
- **Rows:** 300

| Column | Type | Description |
|---|---|---|
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `first_seen_date` | DATE | First day the article had traffic. |
| `last_seen_date` | DATE | Last day the article had traffic. |

### dim_user

Users as TRENDii can identify them. The same person on two publishers or two devices counts as separate users.

- **Grain:** One row per user (publisher + device)
- **Key:** `user_key`
- **Rows:** 131,502

| Column | Type | Description |
|---|---|---|
| `user_key` | VARCHAR | User key = `publisher_id:device_id`. FK -> dim_user. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `device_id` | VARCHAR | Device ID (`did`). Unique only within a publisher. |
| `first_seen_date` | DATE | First day the user was seen. |
| `last_seen_date` | DATE | Last day the user was seen. |
| `page_views` | BIGINT | Number of page views by this user. |
| `latest_user_agent` | VARCHAR | User agent from the most recent page view. |
| `device_type` | VARCHAR | mobile / tablet / desktop, parsed from the user agent (rule-based, approximate). |

### dim_brand

Brands / advertisers.

- **Grain:** One row per brand
- **Key:** `brand_id`
- **Rows:** 5

| Column | Type | Description |
|---|---|---|
| `brand_id` | VARCHAR | Brand ID. In facts and marts this comes from dim_product (trusted), not from the event. FK -> dim_brand. |
| `brand_name` | VARCHAR | Brand / company name (from campaign data). |
| `brand_domain` | VARCHAR | Brand main website domain. |

### dim_product

Product catalogue. The trusted source of each product's brand.

- **Grain:** One row per product
- **Key:** `product_id`
- **Rows:** 245

| Column | Type | Description |
|---|---|---|
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `brand_id` | VARCHAR | Brand ID. In facts and marts this comes from dim_product (trusted), not from the event. FK -> dim_brand. |
| `brand_name` | VARCHAR | Brand / company name (from campaign data). |
| `sku` | VARCHAR | Brand's own product code (Stock Keeping Unit). |
| `product_name` | VARCHAR | Product name. |
| `product_url` | VARCHAR | Product page link. |
| `image_url` | VARCHAR | Product image link. |
| `rrp` | DOUBLE | Recommended retail price (`price` in source). |
| `sale_price` | DOUBLE | Sale price; NULL if not on sale. |
| `current_price` | DOUBLE | sale_price if on sale, otherwise rrp. |
| `is_on_sale` | BOOLEAN | TRUE if sale_price is lower than rrp. |
| `created_at` | DATE | Date TRENDii ingested the product. |

### dim_campaign

Advertiser campaigns with full change history, so events are matched to the rate valid on their date.

- **Grain:** One row per campaign version (SCD Type 2)
- **Key:** `campaign_sk`
- **Rows:** 6

| Column | Type | Description |
|---|---|---|
| `campaign_sk` | VARCHAR | Surrogate key of the campaign *version* valid on event_date. FK -> dim_campaign. NULL if no campaign was running. |
| `campaign_id` | VARCHAR | Business ID of the campaign (same across SCD versions). |
| `campaign_name` | VARCHAR | Campaign name. |
| `brand_id` | VARCHAR | Brand ID. In facts and marts this comes from dim_product (trusted), not from the event. FK -> dim_brand. |
| `billing_type` | VARCHAR | How the campaign pays: CPC (per click), CPM (per 1,000 impressions) or CPA (commission on sales). |
| `is_billing_type_inferred` | BOOLEAN | TRUE if product_type was blank in the source and billing_type was inferred from the rate column that is filled. |
| `cpc_rate` | DOUBLE | Amount earned per click (CPC campaigns). |
| `cpm_rate` | DOUBLE | Amount earned per 1,000 impressions (CPM campaigns). |
| `cpa_percentage` | DOUBLE | Commission share of a sale (CPA campaigns), e.g. 0.08 = 8%. |
| `company_name` | VARCHAR | Advertiser company name. |
| `company_domain` | VARCHAR | Advertiser main website domain. |
| `created_at` | DATE | Date the campaign was created. |
| `valid_from` | DATE | First day this campaign version applies (inclusive). |
| `valid_to` | DATE | Last day this campaign version applies (inclusive). 9999-12-31 = current version. |
| `current_record` | BOOLEAN | TRUE if this is the current campaign version. |


## Marts

### agg_daily_domain_funnel

Daily traffic and ad funnel KPIs per website. Ready for dashboards.

- **Grain:** One row per day per publisher
- **Key:** `event_date, publisher_id`
- **Rows:** 93

| Column | Type | Description |
|---|---|---|
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `tagloads` | BIGINT | Number of page views where the TRENDii tag loaded. |
| `users` | BIGINT | Distinct users that day. |
| `page_views_with_mount` | BIGINT | Page views where ads mounted. |
| `mounted_images` | BIGINT | Number of images that had an ad unit mounted. |
| `page_views_with_impression` | BIGINT | Page views where products were shown. |
| `product_impressions` | BIGINT | Product impressions (de-duplicated). |
| `clicks` | BIGINT | Number of product clicks. |
| `mount_rate` | DOUBLE | page_views_with_mount / tagloads (0-1). |
| `click_through_rate` | DOUBLE | clicks / impressions. |

### agg_daily_product_performance

Daily product performance with estimated revenue.

- **Grain:** One row per day per product per campaign version
- **Key:** `event_date, product_id, campaign_id`
- **Rows:** 124

| Column | Type | Description |
|---|---|---|
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `product_name` | VARCHAR | Product name. |
| `brand_id` | VARCHAR | Brand ID. In facts and marts this comes from dim_product (trusted), not from the event. FK -> dim_brand. |
| `brand_name` | VARCHAR | Brand / company name (from campaign data). |
| `campaign_id` | VARCHAR | Business ID of the campaign (same across SCD versions). |
| `campaign_name` | VARCHAR | Campaign name. |
| `billing_type` | VARCHAR | How the campaign pays: CPC (per click), CPM (per 1,000 impressions) or CPA (commission on sales). |
| `impressions` | BIGINT | Number of product impressions (de-duplicated: page view x image x product). |
| `clicks` | BIGINT | Number of product clicks. |
| `click_through_rate` | DOUBLE | clicks / impressions. |
| `estimated_revenue` | DOUBLE | CPC: clicks x cpc_rate. CPM: impressions / 1000 x cpm_rate. CPA: NULL (needs sales data, not provided). |


## Analysis outputs

### ans_q1_top_articles_by_domain

Q1 answer.

- **Grain:** One row per ranked article
- **Key:** `domain, article_url`
- **Rows:** 15

| Column | Type | Description |
|---|---|---|
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `traffic_rank` | BIGINT | Rank within the domain by tagloads (ties share a rank). |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `tagloads` | BIGINT | Number of page views where the TRENDii tag loaded. |

### ans_q2_top_clicked_products_final_week

Q2 answer.

- **Grain:** One row per ranked product
- **Key:** `brand_name, product_id`
- **Rows:** 4

| Column | Type | Description |
|---|---|---|
| `week_start` | DATE | First day of the "final week" window. |
| `week_end` | DATE | Last day of the dataset = last day of the window. |
| `brand_name` | VARCHAR | Brand / company name (from campaign data). |
| `click_rank` | BIGINT | Rank within the brand by clicks in the final week (ties share a rank). |
| `product_name` | VARCHAR | Product name. |
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `clicks` | BIGINT | Number of product clicks. |

### ans_q3_top_product_per_campaign

Q3 answer.

- **Grain:** One row per campaign
- **Key:** `campaign_id`
- **Rows:** 4

| Column | Type | Description |
|---|---|---|
| `campaign_name` | VARCHAR | Campaign name. |
| `campaign_id` | VARCHAR | Business ID of the campaign (same across SCD versions). |
| `billing_type` | VARCHAR | How the campaign pays: CPC (per click), CPM (per 1,000 impressions) or CPA (commission on sales). |
| `product_name` | VARCHAR | Product name. |
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `impressions` | BIGINT | Number of product impressions (de-duplicated: page view x image x product). |
| `raw_impression_occurrences` | BIGINT | Impressions before de-duplication, for comparison. |

### ans_q4_mount_rate_by_domain

Q4 answer.

- **Grain:** One row per domain + total
- **Key:** `domain`
- **Rows:** 4

| Column | Type | Description |
|---|---|---|
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `tagloads` | BIGINT | Number of page views where the TRENDii tag loaded. |
| `mounts` | BIGINT | Page views with a Mounts event. |
| `mount_rate_pct` | DOUBLE | mounts / tagloads x 100. |
| `mounted_images` | BIGINT | Number of images that had an ad unit mounted. |
| `mounted_images_per_tagload` | DOUBLE | Alternative reading: image mounts / tagloads. |

### ans_q5_unique_users_advertised

Q5 answer.

- **Grain:** One row per domain + total
- **Key:** `domain`
- **Rows:** 4

| Column | Type | Description |
|---|---|---|
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `users_advertised_to` | BIGINT | Distinct users with at least one product impression. |
| `total_users` | BIGINT | All distinct users seen. |
| `pct_of_users` | DOUBLE | users_advertised_to / total_users x 100. |


## Staging

### audit_load_counts

How many rows each cleaning step read, rejected or removed as duplicates. Reported by warn-level tests on every run.

- **Grain:** One row per cleaning step and metric
- **Key:** `model, metric`
- **Rows:** 8

| Column | Type | Description |
|---|---|---|
| `model` | VARCHAR | The model (table) that recorded the count. |
| `metric` | VARCHAR | What was counted. |
| `value` | BIGINT | Number of rows. |

### stg_events

All valid events, de-duplicated on event_id, with event_context flattened.

- **Grain:** One row per event
- **Key:** `event_id`
- **Rows:** 1,295,289

| Column | Type | Description |
|---|---|---|
| `event_id` | VARCHAR | Unique event ID (`eid`) from event_context. |
| `event_name` | VARCHAR | TagLoaded, Mounts, ProductImpressions or ProductClick. |
| `event_created_at` | TIMESTAMP | When the event was ingested (not generated). |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `device_id` | VARCHAR | Device ID (`did`). Unique only within a publisher. |
| `user_agent` | VARCHAR | Browser user agent string. |
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `event_data` | STRUCT (nested) | Event-specific payload (nested). Unpacked by the other staging tables. |
| `source_file` | VARCHAR | Parquet file the row was read from (lineage). |

### stg_events_rejected

Quarantine: events that failed validation. Empty for the provided data.

- **Grain:** One row per rejected event
- **Key:** `-`
- **Rows:** 0

| Column | Type | Description |
|---|---|---|
| `event_id` | VARCHAR | Unique event ID (`eid`) from event_context. |
| `event_name` | VARCHAR | Event type as received. |
| `event_created_at` | TIMESTAMP | Ingestion time (NULL if unparseable). |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `device_id` | VARCHAR | Device ID (`did`). Unique only within a publisher. |
| `user_agent` | VARCHAR | Browser user agent string. |
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `event_data` | STRUCT (nested) | Event payload as received. |
| `source_file` | VARCHAR | Parquet file the row was read from (lineage). |
| `reject_reason` | VARCHAR | Why the event was rejected. |

### stg_tagloads

TagLoaded events.

- **Grain:** One row per page view
- **Key:** `page_view_id`
- **Rows:** 164,663

| Column | Type | Description |
|---|---|---|
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `event_id` | VARCHAR | Unique event ID (`eid`) from event_context. |
| `tagloaded_at` | TIMESTAMP | Ingestion time of the TagLoaded event. |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `device_id` | VARCHAR | Device ID (`did`). Unique only within a publisher. |
| `user_agent` | VARCHAR | Browser user agent string. |

### stg_mounts

Mounts events with mounts[] unnested.

- **Grain:** One row per page view x image
- **Key:** `page_view_id, image_id`
- **Rows:** 1,629,474

| Column | Type | Description |
|---|---|---|
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `event_id` | VARCHAR | Unique event ID (`eid`) from event_context. |
| `mounted_at` | TIMESTAMP | Ingestion time of the Mounts event. |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `device_id` | VARCHAR | Device ID (`did`). Unique only within a publisher. |
| `image_id` | VARCHAR | ID of the image an ad unit was placed on. Unique within a page view. |
| `mount_index` | BIGINT | Position of the mount on the page; 0 = highest. |

### stg_product_impressions

ProductImpressions events with products[] unnested.

- **Grain:** One row per product entry in an impression event (raw, not de-duplicated)
- **Key:** `-`
- **Rows:** 4,744,416

| Column | Type | Description |
|---|---|---|
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `event_id` | VARCHAR | Unique event ID (`eid`) from event_context. |
| `impressed_at` | TIMESTAMP | Ingestion time of the event. |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `device_id` | VARCHAR | Device ID (`did`). Unique only within a publisher. |
| `image_id` | VARCHAR | ID of the image an ad unit was placed on. Unique within a page view. |
| `product_position` | BIGINT | Position of the product in the impression's products[] list (1 = first). |
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `event_brand_id` | VARCHAR | brand_id as sent in the event payload. **Unreliable**: disagrees with dim_product for ~75% of rows. Kept for audit only. |
| `event_product_name` | VARCHAR | Product name as sent in the event payload. |
| `advertised_price` | DOUBLE | Product price shown in the ad at the time of the event (`product_price` in the event). |
| `event_product_url` | VARCHAR | Product URL as sent in the event payload (may be an affiliate link). |

### stg_product_clicks

ProductClick events.

- **Grain:** One row per click
- **Key:** `click_id`
- **Rows:** 1,402

| Column | Type | Description |
|---|---|---|
| `click_id` | VARCHAR | Unique ID of a click. |
| `page_view_id` | VARCHAR | Page View ID (`pvid`). One page load; regenerated on refresh. |
| `event_id` | VARCHAR | Unique event ID (`eid`) from event_context. |
| `clicked_at` | TIMESTAMP | Ingestion time of the event. |
| `event_date` | DATE | Day the event was generated, from the partition file name (YYYY-MM-DD.parquet). Use this for daily reporting. |
| `publisher_id` | BIGINT | Publisher ID. FK -> dim_publisher. |
| `domain` | VARCHAR | Publisher website domain, lower-cased (e.g. 7news.com.au). |
| `article_url` | VARCHAR | URL of the article (without protocol). Natural key of an article. FK -> dim_article. |
| `device_id` | VARCHAR | Device ID (`did`). Unique only within a publisher. |
| `image_id` | VARCHAR | ID of the image an ad unit was placed on. Unique within a page view. |
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `event_brand_id` | VARCHAR | brand_id as sent in the event payload. **Unreliable**: disagrees with dim_product for ~75% of rows. Kept for audit only. |
| `event_product_name` | VARCHAR | Product name as sent in the event payload. |
| `advertised_price` | DOUBLE | Product price shown in the ad at the time of the event (`product_price` in the event). |
| `event_product_url` | VARCHAR | Product URL as sent in the event payload (may be an affiliate link). |

### stg_products

Typed copy of dim_product.csv.

- **Grain:** One row per product
- **Key:** `product_id`
- **Rows:** 245

| Column | Type | Description |
|---|---|---|
| `product_id` | VARCHAR | Product ID. FK -> dim_product. |
| `brand_id` | VARCHAR | Brand ID. In facts and marts this comes from dim_product (trusted), not from the event. FK -> dim_brand. |
| `sku` | VARCHAR | Brand product code. |
| `product_name` | VARCHAR | Product name. |
| `product_url` | VARCHAR | Product page link. |
| `image_url` | VARCHAR | Product image link. |
| `price` | DOUBLE | RRP. |
| `sale_price` | DOUBLE | Sale price; NULL if not on sale. |
| `created_at` | DATE | Date TRENDii ingested the product. |

### stg_campaigns

Typed copy of dim_campaign.csv.

- **Grain:** One row per campaign version
- **Key:** `campaign_id, valid_from`
- **Rows:** 6

| Column | Type | Description |
|---|---|---|
| `campaign_id` | VARCHAR | Business ID of the campaign (same across SCD versions). |
| `campaign_name` | VARCHAR | Campaign name. |
| `brand_id` | VARCHAR | Brand ID. In facts and marts this comes from dim_product (trusted), not from the event. FK -> dim_brand. |
| `product_type` | VARCHAR | Billing type as given in the source file (can be blank). |
| `cpc_rate` | DOUBLE | Amount earned per click (CPC campaigns). |
| `cpm_rate` | DOUBLE | Amount earned per 1,000 impressions (CPM campaigns). |
| `cpa_percentage` | DOUBLE | Commission share of a sale (CPA campaigns), e.g. 0.08 = 8%. |
| `company_name` | VARCHAR | Advertiser company name. |
| `company_domain` | VARCHAR | Advertiser main website domain. |
| `created_at` | DATE | Date the campaign was created. |
| `valid_from` | DATE | First day this campaign version applies (inclusive). |
| `valid_to` | DATE | Last day this campaign version applies (inclusive). 9999-12-31 = current version. |
| `current_record` | BOOLEAN | TRUE if this is the current campaign version. |

