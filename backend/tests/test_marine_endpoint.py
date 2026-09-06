from fastapi.testclient import TestClient

from app.ingestion.marine import ingest_pfz_zones
from app.main import app
from app.providers.marine import PfzZoneData
from tests.conftest import _FakeMarineProvider

client = TestClient(app)


def test_list_pfz_zones_returns_ingested_rows(clean_pfz_zones):
    zone = PfzZoneData(
        external_id="pfzlines.endpoint-test",
        category="ghrsst",
        sector_boundary=2,
        sector_name="Test Sector",
        julian_day="248",
        serial_number="099",
        year=2021,
        uid=2021248099,
        length_km=12.5,
        geometry={"type": "MultiLineString", "coordinates": [[[10.0, 10.0], [11.0, 11.0]]]},
        raw_payload={"id": "pfzlines.endpoint-test", "secret": "should not leak"},
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    response = client.get("/marine/pfz-zones")

    assert response.status_code == 200
    body = response.json()
    matching = [z for z in body if z["external_id"] == "pfzlines.endpoint-test"]
    assert len(matching) == 1
    assert matching[0]["sector_name"] == "Test Sector"
    assert matching[0]["geometry"] == zone.geometry
    assert "raw_payload" not in matching[0]
