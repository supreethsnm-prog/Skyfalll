from sqlalchemy import select

from app.db import get_engine
from app.ingestion.alerts import ingest_alerts
from app.models import Alert
from app.providers.warning import AlertData
from tests.conftest import FakeWarningProvider


def test_ingest_alerts_removes_rows_absent_from_the_latest_fetch(clean_alerts_table):
    stale_alert = AlertData(
        external_id="resolved-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Old", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([stale_alert]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1  # sanity check before reconciliation

    still_active = AlertData(
        external_id="active-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="New", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([still_active]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert {r["external_id"] for r in rows} == {"active-1"}


def test_ingest_alerts_keeps_rows_still_present_in_the_latest_fetch(clean_alerts_table):
    alert = AlertData(
        external_id="persistent-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Still here", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([alert]))
    ingest_alerts(FakeWarningProvider([alert]))  # same external_id, second run

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "persistent-1"


def test_ingest_alerts_does_not_wipe_existing_rows_on_an_empty_fetch(clean_alerts_table):
    alert = AlertData(
        external_id="keep-me-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Should survive", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([alert]))

    count = ingest_alerts(FakeWarningProvider([]))  # empty fetch

    assert count == 0
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "keep-me-1"


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
