const constants = require("../../includes/constants.js");

declare({
  database: constants.PROJECT_ID,
  schema: constants.DATASET,
  name: constants.RAW_POWER_STAT_TABLE,
  description: "Raw/Bronze SCADA power station telemetry connected from MEW database."
});

declare({
  database: constants.PROJECT_ID,
  schema: constants.DATASET,
  name: constants.RAW_GENERATOR_TABLE,
  description: "Raw/Bronze generator unit telemetry connected from MEW database."
});
