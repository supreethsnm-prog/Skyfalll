from fastapi import FastAPI

from app.db import check_db_connection
from app.ingestion.alerts import ingest_alerts
from app.providers.sachet import SACHETWarningProvider

app = FastAPI(title="WeatherGPT Backend")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/db")
def health_db() -> dict[str, str]:
    check_db_connection()
    return {"status": "ok", "db": "connected"}


@app.post("/internal/ingest/alerts")
def trigger_alert_ingestion() -> dict[str, int]:
    count = ingest_alerts(SACHETWarningProvider())
    return {"ingested": count}
