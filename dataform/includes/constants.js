const PROJECT_ID = dataform.projectConfig.defaultProject;
const LOCATION = dataform.projectConfig.defaultLocation;

// Unified Single Dataset Architecture
const DATASET = dataform.projectConfig.vars.targetDataset || dataform.projectConfig.defaultDataset || "mew_analytics";

// Customer-configurable raw/bronze source table names within the same dataset
const RAW_POWER_STAT_TABLE = dataform.projectConfig.vars.rawPowerStatTable || "POWER_STAT";
const RAW_GENERATOR_TABLE = dataform.projectConfig.vars.rawGeneratorTable || "GENERATOR_READINGS";

// Backward-compatible aliases all pointing to the unified dataset
const BRONZE_DS = DATASET;
const SILVER_DS = DATASET;
const GOLD_DS = DATASET;
const DIMENSIONS_DS = DATASET;

const TIMEZONE = dataform.projectConfig.vars.timezone || "Asia/Kuwait";

const THRESHOLDS = {
  MAX_LOAD_MW: Number(dataform.projectConfig.vars.maxLoadThresholdMw || 25000),
  MIN_TEMP_C: Number(dataform.projectConfig.vars.minTempThresholdC || -10.0),
  MAX_TEMP_C: Number(dataform.projectConfig.vars.maxTempThresholdC || 70.0),
  MIN_FREQ_HZ: Number(dataform.projectConfig.vars.minFrequencyHz || 35.0),
  MAX_FREQ_HZ: Number(dataform.projectConfig.vars.maxFrequencyHz || 65.0),
  ALERT_LOAD_MW: Number(dataform.projectConfig.vars.criticalLoadAlertMw || 12000)
};

module.exports = {
  PROJECT_ID,
  LOCATION,
  DATASET,
  RAW_POWER_STAT_TABLE,
  RAW_GENERATOR_TABLE,
  BRONZE_DS,
  SILVER_DS,
  GOLD_DS,
  DIMENSIONS_DS,
  TIMEZONE,
  THRESHOLDS
};
