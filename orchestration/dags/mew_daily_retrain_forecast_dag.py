"""
MEW Kuwait Energy Intelligence Platform
Daily BQML Model Retraining & 30-Day Peak Load Forecast Archival DAG
Target: Google Cloud Managed Service for Apache Airflow (Cloud Composer 2 / 3)
Schedule: Daily at 01:00 AM Asia/Kuwait (22:00 UTC)
"""

from __future__ import annotations

import datetime
import os

from airflow.models.dag import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator

DEFAULT_PROJECT_ID = os.environ.get("GCP_PROJECT", os.environ.get("GCP_PROJECT_ID", "electric-load-demo"))
DEFAULT_LOCATION = os.environ.get("GCP_LOCATION", "europe-west4")
DEFAULT_DATASET = os.environ.get("BQ_DATASET", "mew_analytics")

PROJECT_ID_JINJA = "{{ var.value.get('gcp_project_id', '" + DEFAULT_PROJECT_ID + "') }}"
LOCATION_JINJA = "{{ var.value.get('gcp_location', '" + DEFAULT_LOCATION + "') }}"
DATASET_JINJA = "{{ var.value.get('bq_dataset', '" + DEFAULT_DATASET + "') }}"

default_args = {
    "owner": "mew-grid-data-science",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": datetime.timedelta(minutes=5),
}

with DAG(
    dag_id="mew_daily_retrain_forecast_dag",
    description="Daily BQML Retraining (ARIMA_PLUS & Boosted Tree Regressor) and 30-Day Forecast Archival",
    default_args=default_args,
    schedule="0 22 * * *",  # 01:00 AM Asia/Kuwait (UTC+3)
    start_date=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
    catchup=False,
    max_active_runs=1,
    tags=["mew", "bqml", "forecast", "daily-retrain"],
) as dag:

    execute_retraining_and_archive = BigQueryInsertJobOperator(
        task_id="execute_retraining_and_archive",
        project_id=PROJECT_ID_JINJA,
        location=LOCATION_JINJA,
        configuration={
            "query": {
                "query": f"CALL `{PROJECT_ID_JINJA}.{DATASET_JINJA}.sp_daily_model_retrain_and_archive`();",
                "useLegacySql": False,
            }
        },
    )

    verify_forecast_freshness = BigQueryInsertJobOperator(
        task_id="verify_forecast_freshness",
        project_id=PROJECT_ID_JINJA,
        location=LOCATION_JINJA,
        configuration={
            "query": {
                "query": f"""
                    ASSERT (
                        SELECT COUNT(1)
                        FROM `{PROJECT_ID_JINJA}.{DATASET_JINJA}.forecast_30d`
                    ) >= 30 AS 'Expected at least 30 daily forecast rows in forecast_30d view';
                """,
                "useLegacySql": False,
            }
        },
    )

    execute_retraining_and_archive >> verify_forecast_freshness
