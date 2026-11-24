-- dim_brand: one row per brand. Brand names are not in dim_product, so
-- they come from the current campaign record of each brand.
CREATE OR REPLACE TABLE dim_brand AS
WITH all_brands AS (
    SELECT brand_id FROM stg_products
    UNION
    SELECT brand_id FROM stg_campaigns
),
campaign_names AS (
    SELECT
        brand_id,
        arg_max(company_name,   valid_to) AS brand_name,
        arg_max(company_domain, valid_to) AS brand_domain
    FROM stg_campaigns
    GROUP BY brand_id
)
SELECT
    b.brand_id,
    coalesce(c.brand_name, 'Unknown brand ' || b.brand_id) AS brand_name,
    c.brand_domain
FROM all_brands b
LEFT JOIN campaign_names c USING (brand_id);
