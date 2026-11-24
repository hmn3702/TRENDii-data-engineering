-- dim_product: product attributes + brand + derived pricing fields.
-- This is the trusted source of a product's brand (the brand_id inside
-- impression/click events disagrees with it ~75% of the time).
CREATE OR REPLACE TABLE dim_product AS
SELECT
    p.product_id,
    p.brand_id,
    b.brand_name,
    p.sku,
    p.product_name,
    p.product_url,
    p.image_url,
    p.price                                   AS rrp,
    p.sale_price,
    coalesce(p.sale_price, p.price)           AS current_price,
    p.sale_price IS NOT NULL AND p.sale_price < p.price AS is_on_sale,
    p.created_at
FROM stg_products p
LEFT JOIN dim_brand b USING (brand_id);
