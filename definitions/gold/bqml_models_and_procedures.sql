-- =============================================================================
-- MEW Energy Intelligence Platform - Gold Layer BQML Models & Stored Procedures
-- All objects reside in the unified dataset (`electric-load-demo.mew_analytics` by default)
-- Completely idempotent DDL and DML operations
-- =============================================================================

-- 1. Historical Audit Storage DDL
CREATE TABLE IF NOT EXISTS `electric-load-demo.mew_analytics.forecast_30d_history` (
    forecast_execution_time TIMESTAMP,
    forecast_timestamp TIMESTAMP,
    forecast_value FLOAT64,
    standard_error FLOAT64,
    confidence_level FLOAT64,
    prediction_interval_lower_bound FLOAT64,
    prediction_interval_upper_bound FLOAT64
)
PARTITION BY DATE(forecast_execution_time)
CLUSTER BY forecast_execution_time, forecast_timestamp;

CREATE TABLE IF NOT EXISTS `electric-load-demo.mew_analytics.forecast_explain_30d_history` (
    forecast_execution_time TIMESTAMP,
    time_series_timestamp TIMESTAMP,
    time_series_type STRING,
    time_series_data FLOAT64,
    standard_error FLOAT64,
    confidence_level FLOAT64,
    prediction_interval_lower_bound FLOAT64,
    prediction_interval_upper_bound FLOAT64,
    trend FLOAT64,
    seasonal_period_weekly FLOAT64,
    seasonal_period_yearly FLOAT64,
    holiday_effect FLOAT64,
    spikes_and_dips FLOAT64
)
PARTITION BY DATE(forecast_execution_time)
CLUSTER BY forecast_execution_time, time_series_timestamp;

CREATE TABLE IF NOT EXISTS `electric-load-demo.mew_analytics.realtime_predictions_5min` (
    timestamp TIMESTAMP,
    full_load_mw FLOAT64,
    predicted_max_load_mw FLOAT64,
    deviation_pct FLOAT64,
    is_anomaly BOOL,
    evaluated_at TIMESTAMP
)
PARTITION BY DATE(timestamp);

CREATE TABLE IF NOT EXISTS `electric-load-demo.mew_analytics.realtime_active_alerts` (
    timestamp TIMESTAMP,
    full_load_mw FLOAT64,
    predicted_max_load_mw FLOAT64,
    deviation_pct FLOAT64,
    is_anomaly BOOL,
    alert_severity STRING,
    alert_message STRING
);

-- 2. Initial Model Definitions (Pre-requisite for procedure validation)
CREATE OR REPLACE MODEL `electric-load-demo.mew_analytics.daily_peak_forecast_model`
OPTIONS (
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'day_ts',
  time_series_data_col = 'peak_load_mw',
  data_frequency = 'DAILY',
  holiday_region = 'EMEA',
  auto_arima = TRUE
) AS
SELECT day_ts, peak_load_mw
FROM `electric-load-demo.mew_analytics.daily_load`
WHERE day_ts IS NOT NULL AND peak_load_mw IS NOT NULL;

CREATE OR REPLACE MODEL `electric-load-demo.mew_analytics.load_regression_model`
OPTIONS (
  model_type = 'BOOSTED_TREE_REGRESSOR',
  input_label_cols = ['max_load_mw'],
  enable_global_explain = TRUE,
  data_split_method = 'AUTO_SPLIT',
  max_iterations = 25
) AS
SELECT
  max_load_mw, max_temp_c, avg_humidity_pct, hour_of_day, day_of_week,
  is_weekend, season, is_national_day, religious_event,
  avg_active_generators, avg_generation_mw, avg_spinning_reserve_mw,
  load_mw_24h_ago, avg_load_past_24h
FROM `electric-load-demo.mew_analytics.hourly_load`
WHERE max_load_mw IS NOT NULL AND max_temp_c IS NOT NULL;

-- 3. Daily Retraining & Historical Forecast Archival Procedure
CREATE OR REPLACE PROCEDURE `electric-load-demo.mew_analytics.sp_daily_model_retrain_and_archive`()
OPTIONS (strict_mode = false)
BEGIN
  DECLARE execution_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  -- Retrain ARIMA_PLUS Model (Idempotent CREATE OR REPLACE MODEL)
  CREATE OR REPLACE MODEL `electric-load-demo.mew_analytics.daily_peak_forecast_model`
  OPTIONS (
    model_type = 'ARIMA_PLUS',
    time_series_timestamp_col = 'day_ts',
    time_series_data_col = 'peak_load_mw',
    data_frequency = 'DAILY',
    holiday_region = 'EMEA',
    auto_arima = TRUE
  ) AS
  SELECT day_ts, peak_load_mw
  FROM `electric-load-demo.mew_analytics.daily_load`
  WHERE day_ts IS NOT NULL AND peak_load_mw IS NOT NULL;

  -- Retrain Boosted Tree Regressor (Idempotent CREATE OR REPLACE MODEL)
  CREATE OR REPLACE MODEL `electric-load-demo.mew_analytics.load_regression_model`
  OPTIONS (
    model_type = 'BOOSTED_TREE_REGRESSOR',
    input_label_cols = ['max_load_mw'],
    enable_global_explain = TRUE,
    data_split_method = 'AUTO_SPLIT',
    max_iterations = 25
  ) AS
  SELECT
    max_load_mw, max_temp_c, avg_humidity_pct, hour_of_day, day_of_week,
    is_weekend, season, is_national_day, religious_event,
    avg_active_generators, avg_generation_mw, avg_spinning_reserve_mw,
    load_mw_24h_ago, avg_load_past_24h
  FROM `electric-load-demo.mew_analytics.hourly_load`
  WHERE max_load_mw IS NOT NULL AND max_temp_c IS NOT NULL;

  -- Append to Historical Archives
  INSERT INTO `electric-load-demo.mew_analytics.forecast_30d_history`
  SELECT
    execution_ts, forecast_timestamp, forecast_value, standard_error,
    confidence_level, prediction_interval_lower_bound, prediction_interval_upper_bound
  FROM ML.FORECAST(
    MODEL `electric-load-demo.mew_analytics.daily_peak_forecast_model`,
    STRUCT(30 AS horizon, 0.85 AS confidence_level)
  );

  INSERT INTO `electric-load-demo.mew_analytics.forecast_explain_30d_history`
  SELECT
    execution_ts, time_series_timestamp, time_series_type, time_series_data,
    standard_error, confidence_level, prediction_interval_lower_bound,
    prediction_interval_upper_bound, trend, seasonal_period_weekly,
    seasonal_period_yearly, holiday_effect, spikes_and_dips
  FROM ML.EXPLAIN_FORECAST(
    MODEL `electric-load-demo.mew_analytics.daily_peak_forecast_model`,
    STRUCT(30 AS horizon, 0.85 AS confidence_level)
  );

  -- Update Serving Views (Idempotent CREATE OR REPLACE VIEW)
  CREATE OR REPLACE VIEW `electric-load-demo.mew_analytics.forecast_30d` AS
  SELECT * EXCEPT(forecast_execution_time)
  FROM `electric-load-demo.mew_analytics.forecast_30d_history`
  WHERE forecast_execution_time = (
      SELECT MAX(forecast_execution_time) FROM `electric-load-demo.mew_analytics.forecast_30d_history`
  );

  CREATE OR REPLACE VIEW `electric-load-demo.mew_analytics.forecast_explain_30d` AS
  SELECT * EXCEPT(forecast_execution_time)
  FROM `electric-load-demo.mew_analytics.forecast_explain_30d_history`
  WHERE forecast_execution_time = (
      SELECT MAX(forecast_execution_time) FROM `electric-load-demo.mew_analytics.forecast_explain_30d_history`
  );
END;

-- 3. 5-Minute Real-Time Inference & Alerting Procedure
CREATE OR REPLACE PROCEDURE `electric-load-demo.mew_analytics.sp_run_realtime_inference_and_alerts`()
OPTIONS (strict_mode = false)
BEGIN
  DECLARE latest_scada_ts TIMESTAMP;
  SET latest_scada_ts = (
    SELECT COALESCE(MAX(timestamp), CURRENT_TIMESTAMP())
    FROM `electric-load-demo.mew_analytics.realtime_scada_stream_v`
  );

  MERGE `electric-load-demo.mew_analytics.realtime_predictions_5min` T
  USING (
    WITH latest_stream AS (
      SELECT
        timestamp,
        current_load_mw AS full_load_mw,
        temp_c AS max_temp_c,
        humidity_pct AS avg_humidity_pct,
        EXTRACT(HOUR FROM timestamp AT TIME ZONE 'Asia/Kuwait') AS hour_of_day,
        EXTRACT(DAYOFWEEK FROM timestamp AT TIME ZONE 'Asia/Kuwait') AS day_of_week,
        EXTRACT(DAYOFWEEK FROM timestamp AT TIME ZONE 'Asia/Kuwait') IN (6, 7) AS is_weekend,
        CASE 
          WHEN EXTRACT(MONTH FROM timestamp AT TIME ZONE 'Asia/Kuwait') IN (12, 1, 2) THEN 'Winter'
          WHEN EXTRACT(MONTH FROM timestamp AT TIME ZONE 'Asia/Kuwait') IN (3, 4, 5) THEN 'Spring'
          WHEN EXTRACT(MONTH FROM timestamp AT TIME ZONE 'Asia/Kuwait') IN (6, 7, 8) THEN 'Summer'
          ELSE 'Fall'
        END AS season,
        FALSE AS is_national_day,
        'Normal' AS religious_event,
        CAST(active_generators AS FLOAT64) AS avg_active_generators,
        net_generation_mw AS avg_generation_mw,
        available_reserve_mw AS avg_spinning_reserve_mw,
        current_load_mw AS load_mw_24h_ago,
        current_load_mw AS avg_load_past_24h
      FROM `electric-load-demo.mew_analytics.realtime_scada_stream_v`
      WHERE timestamp >= TIMESTAMP_SUB(latest_scada_ts, INTERVAL 60 MINUTE)
      QUALIFY ROW_NUMBER() OVER (PARTITION BY timestamp ORDER BY timestamp DESC) = 1
    ),
    predictions AS (
      SELECT
        timestamp,
        full_load_mw,
        predicted_max_load_mw,
        ABS(full_load_mw - predicted_max_load_mw) / NULLIF(predicted_max_load_mw, 0) AS deviation_pct
      FROM ML.PREDICT(
        MODEL `electric-load-demo.mew_analytics.load_regression_model`,
        (SELECT * FROM latest_stream)
      )
    )
    SELECT
      timestamp, full_load_mw, predicted_max_load_mw, deviation_pct,
      (deviation_pct > 0.15) AS is_anomaly,
      CURRENT_TIMESTAMP() AS evaluated_at
    FROM predictions
  ) S
  ON T.timestamp = S.timestamp
  WHEN MATCHED THEN UPDATE SET
    full_load_mw = S.full_load_mw,
    predicted_max_load_mw = S.predicted_max_load_mw,
    deviation_pct = S.deviation_pct,
    is_anomaly = S.is_anomaly,
    evaluated_at = S.evaluated_at
  WHEN NOT MATCHED THEN INSERT (
    timestamp, full_load_mw, predicted_max_load_mw, deviation_pct, is_anomaly, evaluated_at
  ) VALUES (
    S.timestamp, S.full_load_mw, S.predicted_max_load_mw, S.deviation_pct, S.is_anomaly, S.evaluated_at
  );

  CREATE OR REPLACE TABLE `electric-load-demo.mew_analytics.realtime_active_alerts` AS
  SELECT
    timestamp,
    full_load_mw,
    predicted_max_load_mw,
    deviation_pct,
    is_anomaly,
    CASE
      WHEN predicted_max_load_mw >= 12000 THEN 'CRITICAL_GRID_STRESS'
      WHEN predicted_max_load_mw >= 10500 THEN 'HIGH_DEMAND_WARNING'
      WHEN is_anomaly = TRUE THEN 'STATISTICAL_LOAD_ANOMALY'
      ELSE 'NORMAL'
    END AS alert_severity,
    CONCAT('Grid alert at ', CAST(timestamp AS STRING), ': Forecasted = ', CAST(ROUND(predicted_max_load_mw, 1) AS STRING), ' MW.') AS alert_message
  FROM `electric-load-demo.mew_analytics.realtime_predictions_5min`
  WHERE evaluated_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 15 MINUTE)
    AND (predicted_max_load_mw >= 10500 OR is_anomaly = TRUE);
END;
