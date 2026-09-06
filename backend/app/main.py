from fastapi import FastAPI
from sqlalchemy import select

from app.db import check_db_connection, get_engine
from app.ingestion.alerts import ingest_alerts
from app.models import Alert
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


@app.get("/alerts")
def list_alerts() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    return [
        {k: v for k, v in row.items() if k != "raw_payload"}
        for row in rows
    ]
