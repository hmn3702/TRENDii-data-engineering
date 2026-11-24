-- dim_date: one row per calendar day covered by the event data.
CREATE OR REPLACE TABLE dim_date AS
SELECT
    d::DATE                       AS date_day,
    year(d)                       AS year,
    month(d)                      AS month,
    day(d)                        AS day_of_month,
    isodow(d)                     AS iso_day_of_week,   -- 1 = Monday
    dayname(d)                    AS day_name,
    date_trunc('week', d)::DATE   AS week_start_monday,
    isodow(d) IN (6, 7)           AS is_weekend
FROM range(
    (SELECT min(event_date) FROM stg_events),
    (SELECT max(event_date) FROM stg_events) + INTERVAL 1 DAY,
    INTERVAL 1 DAY
) t(d);
