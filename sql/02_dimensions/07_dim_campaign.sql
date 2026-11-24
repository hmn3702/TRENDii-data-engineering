-- dim_campaign: SCD Type 2 - one row per campaign *version*.
-- campaign_sk is the surrogate key facts point to, so a fact is tied to
-- the rate that was valid on the day the event happened.
-- billing_type: product_type from source; when it is blank (The Iconic
-- campaign) it is inferred from which rate column is filled, and flagged.
CREATE OR REPLACE TABLE dim_campaign AS
SELECT
    md5(campaign_id || '|' || valid_from::VARCHAR)          AS campaign_sk,
    campaign_id,
    campaign_name,
    brand_id,
    coalesce(
        product_type,
        CASE
            WHEN cpc_rate       IS NOT NULL THEN 'CPC'
            WHEN cpm_rate       IS NOT NULL THEN 'CPM'
            WHEN cpa_percentage IS NOT NULL THEN 'CPA'
        END
    )                                                      AS billing_type,
    product_type IS NULL                                   AS is_billing_type_inferred,
    cpc_rate,
    cpm_rate,
    cpa_percentage,
    company_name,
    company_domain,
    created_at,
    valid_from,
    valid_to,
    current_record
FROM stg_campaigns;
