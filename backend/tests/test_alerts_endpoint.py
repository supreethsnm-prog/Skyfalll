from fastapi.testclient import TestClient

from app.ingestion.alerts import ingest_alerts
from app.main import app
from app.providers.warning import AlertData

client = TestClient(app)


class _FakeProvider:
    def __init__(self, alerts: list[AlertData]):
        self._alerts = alerts

    def fetch_alerts(self) -> list[AlertData]:
        return self._alerts


def test_list_alerts_returns_ingested_rows(clean_alerts_table):
    alert = AlertData(
        external_id="endpoint-test-1",
        source="SACHET-SDMA",
        severity="ALERT",
        event_type="Flood",
        area_description="Test District",
        effective_start_time=None,
        effective_end_time=None,
        warning_message="Test warning.",
        severity_color="red",
        latitude=10.0,
        longitude=20.0,
        raw_payload={"identifier": "endpoint-test-1"},
    )
    ingest_alerts(_FakeProvider([alert]))

    response = client.get("/alerts")

    assert response.status_code == 200
    body = response.json()
    matching = [a for a in body if a["external_id"] == "endpoint-test-1"]
    assert len(matching) == 1
    assert matching[0]["severity"] == "ALERT"
    assert matching[0]["area_description"] == "Test District"
