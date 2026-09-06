from sqlalchemy import select

from app.db import get_engine
from app.ingestion.alerts import ingest_alerts
from app.models import Alert
from app.providers.warning import AlertData
from tests.conftest import FakeWarningProvider


def _sample_alert(severity: str = "ALERT") -> AlertData:
    return AlertData(
        external_id="ingest-test-1",
        source="SACHET-SDMA",
        severity=severity,
        event_type="Flood",
        area_description="Test District",
        effective_start_time="Sat Sep 05 16:05:00 IST 2026",
        effective_end_time="Sat Sep 05 18:05:00 IST 2026",
        warning_message="Test warning message.",
        severity_color="red",
        latitude=15.37,
        longitude=75.12,
        raw_payload={"identifier": "ingest-test-1"},
    )


def test_ingest_alerts_inserts_new_alert(clean_alerts_table):
    count = ingest_alerts(FakeWarningProvider([_sample_alert()]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(Alert).where(Alert.external_id == "ingest-test-1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].severity == "ALERT"


def test_ingest_alerts_upserts_existing_alert_by_external_id(clean_alerts_table):
    ingest_alerts(FakeWarningProvider([_sample_alert(severity="ALERT")]))
    count = ingest_alerts(FakeWarningProvider([_sample_alert(severity="WATCH")]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(Alert).where(Alert.external_id == "ingest-test-1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].severity == "WATCH"
