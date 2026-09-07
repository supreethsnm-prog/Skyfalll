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


def test_list_alerts_with_no_location_returns_everything_unfiltered(clean_alerts_table):
    near = AlertData(
        external_id="near-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Near", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.05, longitude=72.87,
        raw_payload={},
    )
    far = AlertData(
        external_id="far-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Far", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=28.6, longitude=77.2,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([near, far]))

    rows = list_alerts()

    assert {r["external_id"] for r in rows} == {"near-1", "far-1"}


def test_list_alerts_filters_to_radius_and_sorts_by_distance(clean_alerts_table):
    # Mumbai coordinates as the query point. "near" is in Mumbai, "far" is
    # Delhi (~1150km away — well outside a 100km radius), "medium" is Pune
    # (~120km from Mumbai — also outside a 100km radius, included here to
    # prove the cutoff is a real distance check, not just "same city").
    near = AlertData(
        external_id="near-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Mumbai", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.06, longitude=72.88,
        raw_payload={},
    )
    far = AlertData(
        external_id="far-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Delhi", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=28.6, longitude=77.2,
        raw_payload={},
    )
    no_coords = AlertData(
        external_id="no-coords-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Unknown", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=None, longitude=None,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([near, far, no_coords]))

    rows = list_alerts(latitude=19.05, longitude=72.87, radius_km=100.0)

    # Only the in-radius alert survives; the far one and the coordinate-less
    # one are both excluded (the latter because relevance can't be assessed
    # without coordinates, not because it's necessarily irrelevant).
    assert [r["external_id"] for r in rows] == ["near-1"]
    assert rows[0]["distance_km"] < 5


def test_list_alerts_sorts_multiple_matches_by_distance(clean_alerts_table):
    closer = AlertData(
        external_id="closer", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Very close", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.06, longitude=72.88,
        raw_payload={},
    )
    farther = AlertData(
        external_id="farther", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Less close", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.5, longitude=73.2,
        raw_payload={},
    )
    # Insert farther first, to prove the result is actually sorted by
    # distance rather than by insertion/id order.
    ingest_alerts(FakeWarningProvider([farther, closer]))

    rows = list_alerts(latitude=19.05, longitude=72.87, radius_km=100.0)

    assert [r["external_id"] for r in rows] == ["closer", "farther"]
    assert rows[0]["distance_km"] < rows[1]["distance_km"]
