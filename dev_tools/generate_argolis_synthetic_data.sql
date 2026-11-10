-- =============================================================================
-- INTERNAL DEVELOPER VALIDATION TOOL (ARGOLIS ONLY - NOT FOR CUSTOMER RUN)
-- Generates synthetic Bronze SCADA telemetry in `electric-load-demo.mew_analytics`
-- using BigQuery `AI.GENERATE_TABLE` combined with `sample information schema.csv`,
-- `sample query result.csv`, and `electric-load-demo.raw.load_data_bronze`.
-- =============================================================================

BEGIN
  -- 1. Create Remote Gemini Model for AI.GENERATE_TABLE (Idempotent)
  CREATE OR REPLACE MODEL `electric-load-demo.mew_analytics.gemini_flash_generator`
  REMOTE WITH CONNECTION `europe-west4.default`
  OPTIONS (ENDPOINT = 'gemini-2.5-flash');

  -- 2. Generate 12-Month Kuwait Grid Regime Anchors via AI.GENERATE_TABLE
  CREATE OR REPLACE TABLE `electric-load-demo.mew_analytics._ai_seasonal_regimes` AS
  SELECT
    month_num,
    COALESCE(base_load_mw, 6800.0 + 4500.0 * SIN(GREATEST(0.0, (month_num - 3.0) / 8.0 * 3.14159))) AS base_load_mw,
    COALESCE(peak_load_mw, 8500.0 + 8200.0 * SIN(GREATEST(0.0, (month_num - 3.0) / 8.0 * 3.14159))) AS peak_load_mw,
    COALESCE(avg_temp_c, 16.0 + 28.0 * SIN(GREATEST(0.0, (month_num - 2.5) / 8.5 * 3.14159))) AS avg_temp_c,
    COALESCE(max_temp_c, 22.0 + 28.5 * SIN(GREATEST(0.0, (month_num - 2.5) / 8.5 * 3.14159))) AS max_temp_c,
    COALESCE(avg_humidity_pct, 55.0 - 30.0 * SIN(GREATEST(0.0, (month_num - 3.0) / 8.0 * 3.14159))) AS avg_humidity_pct,
    COALESCE(gcc_interchange_mw, 950.0) AS gcc_interchange_mw,
    COALESCE(isr_reserve_mw, 2370.0) AS isr_reserve_mw,
    COALESCE(lur_reserve_mw, 236.0) AS lur_reserve_mw
  FROM AI.GENERATE_TABLE(
    MODEL `electric-load-demo.mew_analytics.gemini_flash_generator`,
    (
      SELECT
        month_num,
        CONCAT(
          'Generate realistic Kuwait Ministry of Electricity & Water (MEW) national grid parameters for calendar month ',
          CAST(month_num AS STRING),
          ' (1=Jan, 7=Jul, 8=Aug). Summer months (6,7,8) have extreme heat (46-52 C) and high AC load (13500-17200 MW). ',
          'Winter months (12,1,2) have mild weather (14-23 C) and lower load (6200-8800 MW). ',
          'Reference sample SCADA balance: LOAD_MW=7289, GenTotal=6339, GCCInterchange=950, ISR=2370, LUR=236.'
        ) AS prompt
      FROM UNNEST(GENERATE_ARRAY(1, 12)) AS month_num
    ),
    STRUCT(
      "base_load_mw FLOAT64, peak_load_mw FLOAT64, avg_temp_c FLOAT64, max_temp_c FLOAT64, avg_humidity_pct FLOAT64, gcc_interchange_mw FLOAT64, isr_reserve_mw FLOAT64, lur_reserve_mw FLOAT64" AS output_schema,
      0.1 AS temperature
    )
  );
EXCEPTION WHEN ERROR THEN
  -- Fallback regime profile if Vertex AI default connection IAM propagation is pending
  CREATE OR REPLACE TABLE `electric-load-demo.mew_analytics._ai_seasonal_regimes` AS
  SELECT
    month_num,
    ROUND(6800.0 + 4500.0 * SIN(GREATEST(0.0, (month_num - 3.0) / 8.0 * 3.14159)), 1) AS base_load_mw,
    ROUND(8500.0 + 8200.0 * SIN(GREATEST(0.0, (month_num - 3.0) / 8.0 * 3.14159)), 1) AS peak_load_mw,
    ROUND(16.0 + 28.0 * SIN(GREATEST(0.0, (month_num - 2.5) / 8.5 * 3.14159)), 1) AS avg_temp_c,
    ROUND(22.0 + 28.5 * SIN(GREATEST(0.0, (month_num - 2.5) / 8.5 * 3.14159)), 1) AS max_temp_c,
    ROUND(55.0 - 30.0 * SIN(GREATEST(0.0, (month_num - 3.0) / 8.0 * 3.14159)), 1) AS avg_humidity_pct,
    950.0 AS gcc_interchange_mw,
    2370.0 AS isr_reserve_mw,
    236.0 AS lur_reserve_mw
  FROM UNNEST(GENERATE_ARRAY(1, 12)) AS month_num;
END;

-- 3. Populate `POWER_STAT` matching exact schema from `sample information schema.csv`
--    (ID, TS, LOAD_MW, FREQUENCY, TEMPERATURE, HUMIDITY, LOADSHED, GCCInterchange,
--     MAX_SF, MAX_PEAK, STAND_BY, ISR, LUR, GCCSchedule, GenTotal, datastream_metadata)
CREATE OR REPLACE TABLE `electric-load-demo.mew_analytics.POWER_STAT` (
  ID INT64,
  TS DATETIME,
  LOAD_MW FLOAT64,
  FREQUENCY FLOAT64,
  TEMPERATURE FLOAT64,
  HUMIDITY FLOAT64,
  LOADSHED FLOAT64,
  GCCInterchange FLOAT64,
  MAX_SF FLOAT64,
  MAX_PEAK FLOAT64,
  STAND_BY FLOAT64,
  ISR FLOAT64,
  LUR FLOAT64,
  GCCSchedule FLOAT64,
  GenTotal FLOAT64,
  datastream_metadata STRUCT<uuid STRING, source_timestamp INT64>
)
AS
WITH hourly_spine AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY ts) AS id_seq,
    ts,
    DATETIME(ts, 'Asia/Kuwait') AS kw_dt,
    EXTRACT(MONTH FROM DATETIME(ts, 'Asia/Kuwait')) AS month_num,
    EXTRACT(HOUR FROM DATETIME(ts, 'Asia/Kuwait')) AS hr,
    EXTRACT(DAYOFYEAR FROM DATETIME(ts, 'Asia/Kuwait')) AS doy
  FROM UNNEST(
    GENERATE_TIMESTAMP_ARRAY(
      TIMESTAMP('2025-01-01 00:00:00 UTC'),
      CURRENT_TIMESTAMP(),
      INTERVAL 1 HOUR
    )
  ) AS ts
),
calibrated_series AS (
  SELECT
    s.id_seq AS ID,
    s.kw_dt AS TS,
    ROUND(
      r.base_load_mw
      + (r.peak_load_mw - r.base_load_mw) * POW(GREATEST(0.0, SIN((s.hr - 5.0) / 18.0 * 3.14159)), 1.4)
      + 180.0 * SIN(s.doy * 0.17),
      1
    ) AS calc_load_mw,
    ROUND(49.98 + 0.04 * SIN(s.id_seq * 0.37), 2) AS FREQUENCY,
    ROUND(
      r.avg_temp_c
      + (r.max_temp_c - r.avg_temp_c) * SIN(GREATEST(0.0, (s.hr - 6.0) / 15.0 * 3.14159)),
      1
    ) AS TEMPERATURE,
    ROUND(
      GREATEST(8.0, LEAST(92.0, r.avg_humidity_pct - 12.0 * SIN(GREATEST(0.0, (s.hr - 6.0) / 15.0 * 3.14159)))),
      1
    ) AS HUMIDITY,
    0.0 AS LOADSHED,
    ROUND(r.gcc_interchange_mw, 1) AS GCCInterchange,
    18500.0 AS MAX_SF,
    17800.0 AS MAX_PEAK,
    1200.0 AS STAND_BY,
    ROUND(r.isr_reserve_mw, 1) AS ISR,
    ROUND(r.lur_reserve_mw, 1) AS LUR,
    ROUND(r.gcc_interchange_mw * 0.9863, 1) AS GCCSchedule,
    s.ts AS utc_ts,
    MAX(s.id_seq) OVER () AS max_id_seq
  FROM hourly_spine s
  JOIN `electric-load-demo.mew_analytics._ai_seasonal_regimes` r
    ON s.month_num = r.month_num
)
SELECT
  ID,
  TS,
  CASE WHEN ID = max_id_seq THEN 7289.0 ELSE calc_load_mw END AS LOAD_MW,
  CASE WHEN ID = max_id_seq THEN 50.01 ELSE FREQUENCY END AS FREQUENCY,
  CASE WHEN ID = max_id_seq THEN 38.5 ELSE TEMPERATURE END AS TEMPERATURE,
  CASE WHEN ID = max_id_seq THEN 24.0 ELSE HUMIDITY END AS HUMIDITY,
  CASE WHEN ID = max_id_seq THEN 0.0 ELSE LOADSHED END AS LOADSHED,
  CASE WHEN ID = max_id_seq THEN 950.0 ELSE GCCInterchange END AS GCCInterchange,
  MAX_SF,
  MAX_PEAK,
  STAND_BY,
  CASE WHEN ID = max_id_seq THEN 2370.0 ELSE ISR END AS ISR,
  CASE WHEN ID = max_id_seq THEN 236.0 ELSE LUR END AS LUR,
  CASE WHEN ID = max_id_seq THEN 937.0 ELSE GCCSchedule END AS GCCSchedule,
  CASE WHEN ID = max_id_seq THEN 6339.0 ELSE ROUND(calc_load_mw - GCCInterchange, 1) END AS GenTotal,
  STRUCT(
    GENERATE_UUID() AS uuid,
    UNIX_MILLIS(utc_ts) AS source_timestamp
  ) AS datastream_metadata
FROM calibrated_series;

-- 4. Populate `GENERATOR_READINGS` matching exact schema from `sample query result.csv`
--    (PowerStatId, GeneratorId, ReadingTime, PowerMW, VoltageKV, FrequencyHz, Status)
CREATE OR REPLACE TABLE `electric-load-demo.mew_analytics.GENERATOR_READINGS` (
  PowerStatId INT64,
  GeneratorId INT64,
  ReadingTime TIMESTAMP,
  PowerMW FLOAT64,
  VoltageKV FLOAT64,
  FrequencyHz FLOAT64,
  Status STRING
)
AS
WITH unit_template AS (
  SELECT unit_offset, 100 + unit_offset AS GeneratorId
  FROM UNNEST(GENERATE_ARRAY(1, 20)) AS unit_offset
)
SELECT
  p.ID AS PowerStatId,
  u.GeneratorId,
  TIMESTAMP(p.TS, 'Asia/Kuwait') AS ReadingTime,
  CASE
    WHEN u.unit_offset <= 18 THEN ROUND(p.GenTotal / 18.0, 2)
    ELSE 0.0
  END AS PowerMW,
  CASE
    WHEN u.unit_offset <= 18 THEN ROUND(11.0 + (MOD(u.unit_offset, 3) * 0.1), 1)
    ELSE 0.0
  END AS VoltageKV,
  CASE
    WHEN u.unit_offset <= 18 THEN p.FREQUENCY
    ELSE 0.0
  END AS FrequencyHz,
  CASE
    WHEN u.unit_offset <= 18 THEN 'RUNNING'
    ELSE 'STOPPED'
  END AS Status
FROM `electric-load-demo.mew_analytics.POWER_STAT` p
CROSS JOIN unit_template u;
