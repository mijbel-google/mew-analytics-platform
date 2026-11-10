"""
MEW Kuwait Energy Intelligence Platform
5-Minute Micro-Batch Telemetry & Real-Time Anomaly Inference DAG
Target: Google Cloud Managed Service for Apache Airflow (Cloud Composer 2 / 3)
"""

from __future__ import annotations

import datetime
import json
import os
from typing import Any

from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.providers.google.cloud.operators.dataform import (
    DataformCreateCompilationResultOperator,
    DataformCreateWorkflowInvocationOperator,
)

# Environment defaults (overridable via Airflow Variables at runtime without top-level DB calls)
DEFAULT_PROJECT_ID = os.environ.get("GCP_PROJECT", os.environ.get("GCP_PROJECT_ID", "electric-load-demo"))
DEFAULT_LOCATION = os.environ.get("GCP_LOCATION", "europe-west4")
DEFAULT_DATASET = os.environ.get("BQ_DATASET", "mew_analytics")
DEFAULT_DATAFORM_REPO = os.environ.get("DATAFORM_REPOSITORY", "mew-grid-pipeline")
DEFAULT_PUBSUB_TOPIC = os.environ.get("PUBSUB_ALERT_TOPIC", "grid-stress-alerts")

PROJECT_ID_JINJA = "{{ var.value.get('gcp_project_id', '" + DEFAULT_PROJECT_ID + "') }}"
LOCATION_JINJA = "{{ var.value.get('gcp_location', '" + DEFAULT_LOCATION + "') }}"
DATASET_JINJA = "{{ var.value.get('bq_dataset', '" + DEFAULT_DATASET + "') }}"
DATAFORM_REPO_JINJA = "{{ var.value.get('dataform_repository', '" + DEFAULT_DATAFORM_REPO + "') }}"
RAW_POWER_STAT_JINJA = "{{ var.value.get('raw_power_stat_table', 'POWER_STAT') }}"
RAW_GENERATOR_JINJA = "{{ var.value.get('raw_generator_table', 'GENERATOR_READINGS') }}"
PUBSUB_TOPIC_JINJA = "{{ var.value.get('pubsub_alert_topic', '" + DEFAULT_PUBSUB_TOPIC + "') }}"


def check_and_publish_grid_alerts(
    project_id: str,
    location: str,
    dataset: str,
    pubsub_topic: str,
    **context: Any,
) -> str:
    """
    Idempotently checks `realtime_active_alerts` in the unified BigQuery dataset
    and publishes alert payloads to Cloud Pub/Sub if critical stress or anomalies exist.
    """
    from google.cloud import bigquery
    from google.cloud import pubsub_v1

    bq_client = bigquery.Client(project=project_id, location=location)
    query = f"""
        SELECT
            CAST(timestamp AS STRING) AS timestamp,
            full_load_mw,
            predicted_max_load_mw,
            deviation_pct,
            is_anomaly,
            alert_severity,
            alert_message
        FROM `{project_id}.{dataset}.realtime_active_alerts`
        ORDER BY timestamp DESC
        LIMIT 10
    """
    rows = [dict(row) for row in bq_client.query(query).result()]
    if not rows:
        return "No active grid alerts detected."

    publisher = pubsub_v1.PublisherClient()
    topic_path = (
        pubsub_topic
        if pubsub_topic.startswith("projects/")
        else publisher.topic_path(project_id, pubsub_topic)
    )
    payload = json.dumps(
        {
            "source": "mew_5min_telemetry_inference_dag",
            "alert_count": len(rows),
            "alerts": rows,
        }
    ).encode("utf-8")

    try:
        future = publisher.publish(topic_path, data=payload)
        message_id = future.result(timeout=30)
        return f"Published {len(rows)} alerts to {topic_path} (message_id={message_id})."
    except Exception as exc:
        # Log warning without failing the pipeline if topic has not been subscribed yet
        print(f"Warning: Could not publish to Pub/Sub topic {topic_path}: {exc}")
        return f"Detected {len(rows)} alerts (Pub/Sub publish skipped: {exc})."


default_args = {
    "owner": "mew-grid-engineering",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": datetime.timedelta(minutes=1),
}

with DAG(
    dag_id="mew_5min_telemetry_inference_dag",
    description="5-Minute SCADA Telemetry ELT (Dataform) + BQML Real-Time Anomaly Detection & Alerting",
    default_args=default_args,
    schedule="*/5 * * * *",
    start_date=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
    catchup=False,
    max_active_runs=1,
    tags=["mew", "scada", "microbatch", "bqml", "dataform"],
) as dag:

    # Step 1: Compile Dataform repository with unified dataset & customer raw table names
    compile_dataform = DataformCreateCompilationResultOperator(
        task_id="compile_dataform_repository",
        project_id=PROJECT_ID_JINJA,
        region=LOCATION_JINJA,
        repository_id=DATAFORM_REPO_JINJA,
        compilation_result={
            "git_commitish": "main",
            "code_compilation_config": {
                "default_database": PROJECT_ID_JINJA,
                "default_schema": DATASET_JINJA,
                "assertion_schema": DATASET_JINJA,
                "vars": {
                    "targetDataset": DATASET_JINJA,
                    "rawPowerStatTable": RAW_POWER_STAT_JINJA,
                    "rawGeneratorTable": RAW_GENERATOR_JINJA,
                },
            },
        },
    )

    # Step 2: Execute Dataform workflow invocation for 5-minute incremental models
    invoke_dataform = DataformCreateWorkflowInvocationOperator(
        task_id="invoke_dataform_microbatch",
        project_id=PROJECT_ID_JINJA,
        region=LOCATION_JINJA,
        repository_id=DATAFORM_REPO_JINJA,
        workflow_invocation={
            "compilation_result": "{{ task_instance.xcom_pull('compile_dataform_repository')['name'] }}",
            "invocation_config": {
                "included_tags": ["microbatch_5min"],
                "transitive_dependencies_included": True,
            },
        },
    )

    # Step 3: Run Real-Time BQML Inference & Anomaly Scoring Stored Procedure
    execute_realtime_inference = BigQueryInsertJobOperator(
        task_id="execute_realtime_inference",
        project_id=PROJECT_ID_JINJA,
        location=LOCATION_JINJA,
        configuration={
            "query": {
                "query": f"CALL `{PROJECT_ID_JINJA}.{DATASET_JINJA}.sp_run_realtime_inference_and_alerts`();",
                "useLegacySql": False,
            }
        },
    )

    # Step 4: Evaluate Active Alerts and Publish to Decoupled Pub/Sub Topic
    evaluate_and_publish_alerts = PythonOperator(
        task_id="evaluate_and_publish_alerts",
        python_callable=check_and_publish_grid_alerts,
        op_kwargs={
            "project_id": PROJECT_ID_JINJA,
            "location": LOCATION_JINJA,
            "dataset": DATASET_JINJA,
            "pubsub_topic": PUBSUB_TOPIC_JINJA,
        },
    )

    compile_dataform >> invoke_dataform >> execute_realtime_inference >> evaluate_and_publish_alerts
