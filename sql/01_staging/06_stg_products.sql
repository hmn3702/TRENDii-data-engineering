-- stg_products: typed load of dim_product.csv (explicit schema, no type guessing).
CREATE OR REPLACE TABLE stg_products AS
SELECT
    trim(id)          AS product_id,
    trim(brand_id)    AS brand_id,
    sku,
    name              AS product_name,
    product_url,
    image_url,
    price,
    sale_price,
    created_at
FROM read_csv('{{data_dir}}/dim_product.csv',
    header = true,
    columns = {
        'id': 'VARCHAR', 'brand_id': 'VARCHAR', 'sku': 'VARCHAR', 'name': 'VARCHAR',
        'product_url': 'VARCHAR', 'image_url': 'VARCHAR', 'price': 'DOUBLE',
        'sale_price': 'DOUBLE', 'created_at': 'DATE'
    });
