-- =============================================================================
-- MEW Energy Intelligence Platform - Idempotent Medallion Materialization Script
-- Target Dataset: `__PROJECT_ID__.__DATASET_NAME__`
-- Customer Raw Sources: `__RAW_POWER_STAT_TABLE__` & `__RAW_GENERATOR_TABLE__`
-- =============================================================================

-- 1. Dimension Table: `calendar_reference`
CREATE OR REPLACE TABLE `__PROJECT_ID__.__DATASET_NAME__.calendar_reference`
CLUSTER BY season, religious_event
OPTIONS (
    description = "Official Kuwait civil holidays, Hijri religious observances, and seasonal boundaries (2020-2035)."
) AS
WITH date_spine AS (
    SELECT day AS calendar_date
    FROM UNNEST(GENERATE_DATE_ARRAY('2020-01-01', '2035-12-31')) AS day
)
SELECT
    calendar_date,
    EXTRACT(DAYOFWEEK FROM calendar_date) IN (6, 7) AS is_weekend,
    EXTRACT(DAYOFWEEK FROM calendar_date) AS day_of_week,
    FORMAT_DATE('%B', calendar_date) AS month_name,
    CASE 
        WHEN EXTRACT(MONTH FROM calendar_date) IN (12, 1, 2) THEN 'Winter'
        WHEN EXTRACT(MONTH FROM calendar_date) IN (3, 4, 5) THEN 'Spring'
        WHEN EXTRACT(MONTH FROM calendar_date) IN (6, 7, 8) THEN 'Summer'
        ELSE 'Fall'
    END AS season,
    FORMAT_DATE('%m-%d', calendar_date) IN ('02-25', '02-26') AS is_national_day,
    CASE
        WHEN FORMAT_DATE('%m-%d', calendar_date) = '01-01' THEN TRUE
        WHEN FORMAT_DATE('%m-%d', calendar_date) IN ('02-25', '02-26') THEN TRUE
        WHEN calendar_date = DATE('2025-01-27') THEN TRUE
        WHEN calendar_date BETWEEN DATE('2025-03-30') AND DATE('2025-04-01') THEN TRUE
        WHEN calendar_date = DATE('2025-06-05') THEN TRUE
        WHEN calendar_date BETWEEN DATE('2025-06-06') AND DATE('2025-06-08') THEN TRUE
        WHEN calendar_date = DATE('2025-06-26') THEN TRUE
        WHEN calendar_date = DATE('2025-09-04') THEN TRUE
        WHEN calendar_date = DATE('2026-01-16') THEN TRUE
        WHEN calendar_date BETWEEN DATE('2026-03-20') AND DATE('2026-03-22') THEN TRUE
        WHEN calendar_date = DATE('2026-05-26') THEN TRUE
        WHEN calendar_date BETWEEN DATE('2026-05-27') AND DATE('2026-05-29') THEN TRUE
        WHEN calendar_date = DATE('2026-06-16') THEN TRUE
        WHEN calendar_date = DATE('2026-08-25') THEN TRUE
        WHEN calendar_date = DATE('2027-01-05') THEN TRUE
        WHEN calendar_date BETWEEN DATE('2027-03-10') AND DATE('2027-03-12') THEN TRUE
        WHEN calendar_date = DATE('2027-05-16') THEN TRUE
        WHEN calendar_date BETWEEN DATE('2027-05-17') AND DATE('2027-05-19') THEN TRUE
        WHEN calendar_date = DATE('2027-06-06') THEN TRUE
        WHEN calendar_date = DATE('2027-08-15') THEN TRUE
        ELSE FALSE
    END AS is_public_holiday,
    CASE
        WHEN FORMAT_DATE('%m-%d', calendar_date) = '01-01' THEN 'New_Year'
        WHEN FORMAT_DATE('%m-%d', calendar_date) = '02-25' THEN 'National_Day'
        WHEN FORMAT_DATE('%m-%d', calendar_date) = '02-26' THEN 'Liberation_Day'
        WHEN calendar_date = DATE('2025-01-27') THEN 'Isra_Miraj'
        WHEN calendar_date BETWEEN DATE('2025-03-01') AND DATE('2025-03-29') THEN 'Ramadan'
        WHEN calendar_date BETWEEN DATE('2025-03-30') AND DATE('2025-04-01') THEN 'Eid_Fitr'
        WHEN calendar_date = DATE('2025-06-05') THEN 'Arafat_Day'
        WHEN calendar_date BETWEEN DATE('2025-06-06') AND DATE('2025-06-08') THEN 'Eid_Adha'
        WHEN calendar_date = DATE('2025-06-26') THEN 'Islamic_New_Year'
        WHEN calendar_date = DATE('2025-09-04') THEN 'Mawlid_Nabi'
        WHEN calendar_date = DATE('2026-01-16') THEN 'Isra_Miraj'
        WHEN calendar_date BETWEEN DATE('2026-02-18') AND DATE('2026-03-19') THEN 'Ramadan'
        WHEN calendar_date BETWEEN DATE('2026-03-20') AND DATE('2026-03-22') THEN 'Eid_Fitr'
        WHEN calendar_date = DATE('2026-05-26') THEN 'Arafat_Day'
        WHEN calendar_date BETWEEN DATE('2026-05-27') AND DATE('2026-05-29') THEN 'Eid_Adha'
        WHEN calendar_date = DATE('2026-06-16') THEN 'Islamic_New_Year'
        WHEN calendar_date = DATE('2026-08-25') THEN 'Mawlid_Nabi'
        WHEN calendar_date = DATE('2027-01-05') THEN 'Isra_Miraj'
        WHEN calendar_date BETWEEN DATE('2027-02-08') AND DATE('2027-03-09') THEN 'Ramadan'
        WHEN calendar_date BETWEEN DATE('2027-03-10') AND DATE('2027-03-12') THEN 'Eid_Fitr'
        WHEN calendar_date = DATE('2027-05-16') THEN 'Arafat_Day'
        WHEN calendar_date BETWEEN DATE('2027-05-17') AND DATE('2027-05-19') THEN 'Eid_Adha'
        WHEN calendar_date = DATE('2027-06-06') THEN 'Islamic_New_Year'
        WHEN calendar_date = DATE('2027-08-15') THEN 'Mawlid_Nabi'
        ELSE 'Normal'
    END AS religious_event
FROM date_spine;

-- 2. Silver Table: `load_telemetry_silver`
CREATE TABLE IF NOT EXISTS `__PROJECT_ID__.__DATASET_NAME__.load_telemetry_silver` (
    power_stat_id INT64,
    timestamp TIMESTAMP,
    full_load_mw FLOAT64,
    frequency_hz FLOAT64,
    temp_c FLOAT64,
    humidity_pct FLOAT64,
    loadshed_mw FLOAT64,
    gcc_interchange_mw FLOAT64,
    isr_reserve_mw FLOAT64,
    lur_reserve_mw FLOAT64,
    active_generators INT64,
    total_generator_mw FLOAT64,
    generator_freq_stddev FLOAT64,
    year INT64,
    hour_of_day INT64,
    day_of_week INT64,
    is_weekend BOOL,
    season STRING,
    is_national_day BOOL,
    is_public_holiday BOOL,
    religious_event STRING,
    source_timestamp_ms INT64
)
PARTITION BY DATE(timestamp)
CLUSTER BY season, hour_of_day, religious_event;

MERGE `__PROJECT_ID__.__DATASET_NAME__.load_telemetry_silver` T
USING (
  WITH raw_power_stat AS (
    SELECT
      CAST(ID AS INT64) AS power_stat_id,
      TIMESTAMP(CAST(TS AS DATETIME), 'Asia/Kuwait') AS timestamp,
      CAST(LOAD_MW AS FLOAT64) AS full_load_mw,
      CAST(FREQUENCY AS FLOAT64) AS frequency_hz,
      CAST(TEMPERATURE AS FLOAT64) AS temp_c,
      CAST(HUMIDITY AS FLOAT64) AS humidity_pct,
      COALESCE(CAST(LOADSHED AS FLOAT64), 0.0) AS loadshed_mw,
      COALESCE(CAST(GCCInterchange AS FLOAT64), 0.0) AS gcc_interchange_mw,
      COALESCE(CAST(ISR AS FLOAT64), 2370.0) AS isr_reserve_mw,
      COALESCE(CAST(LUR AS FLOAT64), 236.0) AS lur_reserve_mw,
      COALESCE(CAST(GenTotal AS FLOAT64), CAST(LOAD_MW AS FLOAT64) * 0.87) AS gen_total_mw,
      COALESCE(
        datastream_metadata.source_timestamp,
        UNIX_MILLIS(TIMESTAMP(CAST(TS AS DATETIME), 'Asia/Kuwait'))
      ) AS source_timestamp_ms,
      ROW_NUMBER() OVER(
        PARTITION BY ID, TS
        ORDER BY COALESCE(
          datastream_metadata.source_timestamp,
          UNIX_MILLIS(TIMESTAMP(CAST(TS AS DATETIME), 'Asia/Kuwait'))
        ) DESC
      ) AS dedupe_rank
    FROM `__PROJECT_ID__.__DATASET_NAME__.__RAW_POWER_STAT_TABLE__`
    WHERE
      ID IS NOT NULL
      AND TS IS NOT NULL
      AND LOAD_MW IS NOT NULL
      AND CAST(LOAD_MW AS FLOAT64) BETWEEN 0.0 AND 25000.0
      AND CAST(TEMPERATURE AS FLOAT64) BETWEEN -10.0 AND 70.0
      AND CAST(FREQUENCY AS FLOAT64) BETWEEN 35.0 AND 65.0
  ),
  raw_generator_rollup AS (
    SELECT
      CAST(PowerStatId AS INT64) AS power_stat_id,
      COUNTIF(UPPER(TRIM(Status)) = 'RUNNING') AS active_generators,
      SUM(CASE WHEN UPPER(TRIM(Status)) = 'RUNNING' THEN CAST(PowerMW AS FLOAT64) ELSE 0.0 END) AS total_generator_mw,
      COALESCE(STDDEV_SAMP(NULLIF(CAST(FrequencyHz AS FLOAT64), 0.0)), 0.0) AS generator_freq_stddev
    FROM `__PROJECT_ID__.__DATASET_NAME__.__RAW_GENERATOR_TABLE__`
    GROUP BY power_stat_id
  )
  SELECT
    p.power_stat_id,
    p.timestamp,
    p.full_load_mw,
    p.frequency_hz,
    p.temp_c,
    p.humidity_pct,
    p.loadshed_mw,
    p.gcc_interchange_mw,
    p.isr_reserve_mw,
    p.lur_reserve_mw,
    CASE
      WHEN COALESCE(g.active_generators, 0) > 0 THEN g.active_generators
      ELSE CAST(GREATEST(12, ROUND(p.full_load_mw / 450.0)) AS INT64)
    END AS active_generators,
    CASE
      WHEN COALESCE(g.total_generator_mw, 0.0) > 0.0 THEN g.total_generator_mw
      ELSE COALESCE(p.gen_total_mw, p.full_load_mw - p.gcc_interchange_mw - p.loadshed_mw)
    END AS total_generator_mw,
    COALESCE(g.generator_freq_stddev, 0.01) AS generator_freq_stddev,
    EXTRACT(YEAR FROM p.timestamp AT TIME ZONE 'Asia/Kuwait') AS year,
    EXTRACT(HOUR FROM p.timestamp AT TIME ZONE 'Asia/Kuwait') AS hour_of_day,
    cal.day_of_week,
    cal.is_weekend,
    cal.season,
    cal.is_national_day,
    cal.is_public_holiday,
    cal.religious_event,
    p.source_timestamp_ms
  FROM raw_power_stat p
  LEFT JOIN raw_generator_rollup g ON p.power_stat_id = g.power_stat_id
  JOIN `__PROJECT_ID__.__DATASET_NAME__.calendar_reference` cal
    ON DATE(p.timestamp, 'Asia/Kuwait') = cal.calendar_date
  WHERE p.dedupe_rank = 1
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.power_stat_id, p.timestamp ORDER BY p.source_timestamp_ms DESC) = 1
) S
ON T.power_stat_id = S.power_stat_id AND T.timestamp = S.timestamp
WHEN MATCHED THEN UPDATE SET
  full_load_mw = S.full_load_mw,
  frequency_hz = S.frequency_hz,
  temp_c = S.temp_c,
  humidity_pct = S.humidity_pct,
  loadshed_mw = S.loadshed_mw,
  gcc_interchange_mw = S.gcc_interchange_mw,
  isr_reserve_mw = S.isr_reserve_mw,
  lur_reserve_mw = S.lur_reserve_mw,
  active_generators = S.active_generators,
  total_generator_mw = S.total_generator_mw,
  generator_freq_stddev = S.generator_freq_stddev,
  year = S.year,
  hour_of_day = S.hour_of_day,
  day_of_week = S.day_of_week,
  is_weekend = S.is_weekend,
  season = S.season,
  is_national_day = S.is_national_day,
  is_public_holiday = S.is_public_holiday,
  religious_event = S.religious_event,
  source_timestamp_ms = S.source_timestamp_ms
WHEN NOT MATCHED THEN INSERT ROW;

-- 3. Gold View: `realtime_scada_stream_v`
CREATE OR REPLACE VIEW `__PROJECT_ID__.__DATASET_NAME__.realtime_scada_stream_v` AS
WITH max_ts_ref AS (
  SELECT COALESCE(MAX(timestamp), CURRENT_TIMESTAMP()) AS max_ts
  FROM `__PROJECT_ID__.__DATASET_NAME__.load_telemetry_silver`
),
latest_telemetry AS (
  SELECT
    s.timestamp,
    s.full_load_mw AS current_load_mw,
    COALESCE(s.total_generator_mw, s.full_load_mw - COALESCE(s.gcc_interchange_mw, 950.0) - COALESCE(s.loadshed_mw, 0.0)) AS net_generation_mw,
    COALESCE(s.gcc_interchange_mw, 950.0) AS gcc_exchange_mw,
    COALESCE(s.loadshed_mw, 0.0) AS loadshed_mw,
    COALESCE(s.total_generator_mw * 1.1579, 7340.0) AS gross_production_mw,
    COALESCE(s.isr_reserve_mw, 2370.0) AS available_reserve_mw,
    COALESCE(s.gcc_interchange_mw * 0.9863, 937.0) AS gcc_supplied_mw,
    COALESCE(s.lur_reserve_mw, 236.0) AS gcc_obligation_mw,
    s.temp_c,
    s.humidity_pct,
    s.frequency_hz,
    s.active_generators
  FROM `__PROJECT_ID__.__DATASET_NAME__.load_telemetry_silver` s
  CROSS JOIN max_ts_ref m
  WHERE s.timestamp >= TIMESTAMP_SUB(m.max_ts, INTERVAL 7 DAY)
)
SELECT
  timestamp,
  ROUND(current_load_mw, 1) AS current_load_mw,
  ROUND(net_generation_mw, 1) AS net_generation_mw,
  ROUND(gcc_exchange_mw, 1) AS gcc_exchange_mw,
  ROUND(loadshed_mw, 1) AS loadshed_mw,
  ROUND(gross_production_mw, 1) AS gross_production_mw,
  ROUND(available_reserve_mw, 1) AS available_reserve_mw,
  ROUND(gcc_supplied_mw, 1) AS gcc_supplied_mw,
  ROUND(gcc_obligation_mw, 1) AS gcc_obligation_mw,
  ROUND((gross_production_mw + available_reserve_mw + gcc_supplied_mw - gcc_obligation_mw), 1) AS available_capacity_mw,
  ROUND(((gross_production_mw + available_reserve_mw + gcc_supplied_mw - gcc_obligation_mw) - current_load_mw), 1) AS reserve_margin_mw,
  ROUND(SAFE_DIVIDE(current_load_mw, (gross_production_mw + available_reserve_mw + gcc_supplied_mw - gcc_obligation_mw)) * 100, 2) AS load_percentage,
  CASE
    WHEN loadshed_mw > 0 OR SAFE_DIVIDE(current_load_mw, (gross_production_mw + available_reserve_mw + gcc_supplied_mw - gcc_obligation_mw)) >= 0.95 THEN 'CRITICAL_LOAD_SHED'
    WHEN SAFE_DIVIDE(current_load_mw, (gross_production_mw + available_reserve_mw + gcc_supplied_mw - gcc_obligation_mw)) >= 0.85 THEN 'UNSAFE_OPERATION'
    ELSE 'SAFE_OPERATION'
  END AS operating_status,
  temp_c,
  humidity_pct,
  frequency_hz,
  active_generators
FROM latest_telemetry;

-- 4. Gold Table: `hourly_load`
CREATE OR REPLACE TABLE `__PROJECT_ID__.__DATASET_NAME__.hourly_load`
PARTITION BY DATE(hour_ts)
CLUSTER BY season, is_weekend, religious_event
AS
WITH base_hourly AS (
  SELECT
    TIMESTAMP_TRUNC(timestamp, HOUR) AS hour_ts,
    AVG(full_load_mw) AS avg_load_mw,
    MAX(full_load_mw) AS max_load_mw,
    AVG(temp_c) AS avg_temp_c,
    MAX(temp_c) AS max_temp_c,
    AVG(humidity_pct) AS avg_humidity_pct,
    MAX(loadshed_mw) AS max_loadshed_mw,
    AVG(active_generators) AS avg_active_generators,
    AVG(total_generator_mw) AS avg_generation_mw,
    AVG(isr_reserve_mw) AS avg_spinning_reserve_mw,
    ANY_VALUE(is_national_day) AS is_national_day,
    ANY_VALUE(religious_event) AS religious_event,
    ANY_VALUE(hour_of_day) AS hour_of_day,
    ANY_VALUE(day_of_week) AS day_of_week,
    ANY_VALUE(is_weekend) AS is_weekend,
    ANY_VALUE(season) AS season
  FROM `__PROJECT_ID__.__DATASET_NAME__.load_telemetry_silver`
  GROUP BY hour_ts
)
SELECT
  base_hourly.*,
  COALESCE(LAG(avg_load_mw, 24) OVER (ORDER BY hour_ts), avg_load_mw) AS load_mw_24h_ago,
  COALESCE(AVG(avg_load_mw) OVER (ORDER BY hour_ts ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING), avg_load_mw) AS avg_load_past_24h
FROM base_hourly;

-- 5. Gold Table: `daily_load`
CREATE OR REPLACE TABLE `__PROJECT_ID__.__DATASET_NAME__.daily_load`
PARTITION BY DATE(day_ts)
CLUSTER BY season, religious_event
AS
WITH base_daily AS (
  SELECT
    TIMESTAMP_TRUNC(timestamp, DAY) AS day_ts,
    AVG(full_load_mw) AS avg_load_mw,
    MAX(full_load_mw) AS peak_load_mw,
    AVG(temp_c) AS avg_temp_c,
    MAX(temp_c) AS max_temp_c,
    AVG(humidity_pct) AS avg_humidity_pct,
    SUM(loadshed_mw) AS total_loadshed_mw,
    AVG(active_generators) AS avg_active_generators,
    ANY_VALUE(is_national_day) AS is_national_day,
    ANY_VALUE(religious_event) AS religious_event,
    ANY_VALUE(day_of_week) AS day_of_week,
    ANY_VALUE(is_weekend) AS is_weekend,
    ANY_VALUE(season) AS season
  FROM `__PROJECT_ID__.__DATASET_NAME__.load_telemetry_silver`
  GROUP BY day_ts
)
SELECT
  base_daily.*,
  COALESCE(LAG(avg_load_mw, 1) OVER (ORDER BY day_ts), avg_load_mw) AS load_mw_1d_ago,
  COALESCE(LAG(avg_load_mw, 7) OVER (ORDER BY day_ts), avg_load_mw) AS load_mw_7d_ago,
  COALESCE(AVG(avg_load_mw) OVER (ORDER BY day_ts ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING), avg_load_mw) AS avg_load_past_7d
FROM base_daily;
