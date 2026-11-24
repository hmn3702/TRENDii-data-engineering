-- stg_campaigns: typed load of dim_campaign.csv (SCD Type 2 source).
-- cpm_rate is entirely empty in the file, so auto-detection would make it
-- VARCHAR - hence the explicit schema.
CREATE OR REPLACE TABLE stg_campaigns AS
SELECT
    id::VARCHAR             AS campaign_id,
    name                    AS campaign_name,
    trim(brand_id)          AS brand_id,
    upper(nullif(trim(product_type), '')) AS product_type,
    cpc_rate,
    cpm_rate,
    cpa_percentage,
    company_name,
    company_domain,
    created_at,
    valid_from,
    valid_to,
    current_record
FROM read_csv('{{data_dir}}/dim_campaign.csv',
    header = true,
    columns = {
        'id': 'VARCHAR', 'name': 'VARCHAR', 'brand_id': 'VARCHAR', 'product_type': 'VARCHAR',
        'cpc_rate': 'DOUBLE', 'cpm_rate': 'DOUBLE', 'cpa_percentage': 'DOUBLE',
        'company_name': 'VARCHAR', 'company_domain': 'VARCHAR', 'created_at': 'DATE',
        'valid_from': 'DATE', 'valid_to': 'DATE', 'current_record': 'BOOLEAN'
    });
