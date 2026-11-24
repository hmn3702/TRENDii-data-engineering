-- =====================================================================
-- stg_events
-- Grain : one row per event (event_id = event_context.eid)
-- Source: data/YYYY-MM-DD.parquet  (partitioned by generation date)
-- Notes :
--   * The brief describes the events as JSON; the delivered files are
--     Parquet with nested STRUCT / LIST columns. We flatten event_context
--     here and keep event_data as a struct for the per-event models.
--   * event_date comes from the partition (file name) = generation date.
--     event_created_at is the *ingestion* time and ~0.1% of events are
--     ingested after midnight, so it is not used for daily bucketing.
--   * Rows that fail typing/validation are routed to stg_events_rejected
--     instead of failing the whole load.
--   * Duplicate event ids (re-delivered events) are de-duplicated,
--     keeping the earliest ingested copy.
--   * audit_load_counts records how many rows each cleaning step removed,
--     so de-duplication is visible (it is checked by warn-level tests).
--     Later staging/fact models append their own counts to it.
-- =====================================================================
CREATE OR REPLACE TABLE stg_events_raw AS
SELECT
    event_context.eid                                   AS event_id,
    event_name,
    TRY_CAST(event_created_at AS TIMESTAMP)             AS event_created_at,
    TRY_CAST(regexp_extract(filename, '(\d{4}-\d{2}-\d{2})\.parquet$', 1) AS DATE)
                                                        AS event_date,
    event_context.publisher_id::BIGINT                  AS publisher_id,
    lower(event_context.domain)                         AS domain,
    event_context.url                                   AS article_url,
    event_context.did                                   AS device_id,
    event_context.ua                                    AS user_agent,
    event_context.pvid                                  AS page_view_id,
    event_data,
    filename                                            AS source_file
FROM read_parquet('{{data_dir}}/*.parquet', filename = true, union_by_name = true);

CREATE OR REPLACE TABLE stg_events_rejected AS
SELECT
    *,
    CASE
        WHEN event_id         IS NULL THEN 'missing event_id'
        WHEN page_view_id     IS NULL THEN 'missing page_view_id'
        WHEN event_created_at IS NULL THEN 'unparseable event_created_at'
        WHEN event_date       IS NULL THEN 'cannot derive event_date from file name'
        WHEN event_name NOT IN ('TagLoaded', 'Mounts', 'ProductImpressions', 'ProductClick')
                                      THEN 'unknown event_name'
    END AS reject_reason
FROM stg_events_raw
WHERE event_id IS NULL
   OR page_view_id IS NULL
   OR event_created_at IS NULL
   OR event_date IS NULL
   OR event_name NOT IN ('TagLoaded', 'Mounts', 'ProductImpressions', 'ProductClick');

CREATE OR REPLACE TABLE stg_events AS
SELECT * EXCLUDE (rn)
FROM (
    SELECT
        *,
        row_number() OVER (PARTITION BY event_id ORDER BY event_created_at, source_file) AS rn
    FROM stg_events_raw
    WHERE event_id IS NOT NULL
      AND page_view_id IS NOT NULL
      AND event_created_at IS NOT NULL
      AND event_date IS NOT NULL
      AND event_name IN ('TagLoaded', 'Mounts', 'ProductImpressions', 'ProductClick')
)
WHERE rn = 1;

CREATE OR REPLACE TABLE audit_load_counts AS
SELECT 'stg_events' AS model, 'raw event rows read' AS metric, count(*) AS value FROM stg_events_raw
UNION ALL
SELECT 'stg_events', 'events rejected (invalid)', (SELECT count(*) FROM stg_events_rejected)
UNION ALL
SELECT 'stg_events', 're-delivered events removed (duplicate event_id)',
       (SELECT count(*) FROM stg_events_raw) - (SELECT count(*) FROM stg_events_rejected)
       - (SELECT count(*) FROM stg_events);

DROP TABLE stg_events_raw;
