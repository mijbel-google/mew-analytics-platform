-- =============================================================================
-- MEW Energy Intelligence Platform - Golden SQL Queries Catalog
-- Unified Dataset Architecture (`electric-load-demo.mew_analytics` by default)
-- =============================================================================

-- Query 1: Real-Time Grid Operating Status & Dual Balance Equations
-- User: "ما هي الأحمال الحالية للشبكة وما هو وضع التشغيل والقدرة المتوفرة؟"
SELECT
  timestamp,
  current_load_mw,
  net_generation_mw,
  gcc_exchange_mw,
  loadshed_mw,
  gross_production_mw,
  available_reserve_mw,
  gcc_supplied_mw,
  gcc_obligation_mw,
  available_capacity_mw,
  reserve_margin_mw,
  load_percentage,
  operating_status,
  frequency_hz,
  temp_c
FROM
  `electric-load-demo.mew_analytics.realtime_scada_stream_v`
ORDER BY
  timestamp DESC
LIMIT 1;

-- Query 2: Next 30 Days Expected Peak Demand & Critical Days
-- User: "What is the predicted peak demand for the next 30 days, and which days will cross 10,000 MW?"
SELECT
  DATE(forecast_timestamp) AS forecast_date,
  ROUND(forecast_value, 1) AS predicted_peak_mw,
  ROUND(prediction_interval_lower_bound, 1) AS lower_bound_85pct,
  ROUND(prediction_interval_upper_bound, 1) AS upper_bound_85pct,
  CASE
    WHEN forecast_value >= 12000 THEN 'CRITICAL_PEAK'
    WHEN forecast_value >= 10000 THEN 'HIGH_PEAK'
    ELSE 'NORMAL_PEAK'
  END AS demand_classification
FROM
  `electric-load-demo.mew_analytics.forecast_30d`
ORDER BY
  forecast_date ASC;

-- Query 3: Heat Sensitivity Above 45°C in Summer
-- User: "How does extreme temperature above 45°C impact the daily base-load and peak load during summer?"
SELECT
  season,
  COUNT(1) AS total_days_recorded,
  ROUND(AVG(avg_load_mw), 1) AS average_daily_load_mw,
  ROUND(AVG(peak_load_mw), 1) AS average_peak_load_mw,
  ROUND(MIN(avg_load_mw), 1) AS minimum_base_load_floor_mw,
  ROUND(MAX(peak_load_mw), 1) AS historical_maximum_peak_mw
FROM
  `electric-load-demo.mew_analytics.daily_load`
WHERE
  max_temp_c >= 45.0
  AND season = 'Summer'
GROUP BY
  season;

-- Query 4: Forecast Decomposition & Holiday Driver Attribution
-- User: "How much did religious holidays shift demand in the latest forecast?"
SELECT
  DATE(time_series_timestamp) AS target_date,
  ROUND(time_series_data, 1) AS baseline_trend_mw,
  ROUND(holiday_effect, 1) AS holiday_impact_mw,
  ROUND(seasonal_period_weekly, 1) AS weekly_cycle_mw,
  ROUND(trend, 1) AS underlying_growth_trend_mw
FROM
  `electric-load-demo.mew_analytics.forecast_explain_30d`
WHERE
  LOWER(time_series_type) = 'forecast'
  AND ABS(COALESCE(holiday_effect, 0.0)) > 0.0
ORDER BY
  target_date ASC;
