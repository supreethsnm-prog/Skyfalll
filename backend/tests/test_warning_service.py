from datetime import datetime, timezone

from app.ingestion.alerts import ingest_alerts
from app.warning.service import list_alerts
from tests.conftest import FakeWarningProvider
from app.providers.warning import AlertData


def test_list_alerts_returns_ingested_rows_without_raw_payload(clean_alerts_table):
    alert = AlertData(
        external_id="service-test-1",
        source="SACHET-SDMA",
        severity="Moderate",
        event_type="Flood",
        area_description="Test Area",
        effective_start_time=None,
        effective_end_time=None,
        warning_message="Test warning",
        severity_color=None,
        latitude=19.08,
        longitude=72.88,
        raw_payload={"secret": "should not leak"},
    )
    ingest_alerts(FakeWarningProvider([alert]))

    rows = list_alerts()

    matching = [r for r in rows if r["external_id"] == "service-test-1"]
    assert len(matching) == 1
    assert matching[0]["severity"] == "Moderate"
    assert "raw_payload" not in matching[0]
