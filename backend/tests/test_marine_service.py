from app.ingestion.marine import ingest_pfz_zones
from app.marine.service import list_pfz_zones
from app.providers.marine import PfzZoneData
from tests.conftest import _FakeMarineProvider


def test_list_pfz_zones_returns_ingested_rows_without_raw_payload(clean_pfz_zones):
    zone = PfzZoneData(
        external_id="service-test-1",
        category="ghrsst",
        sector_boundary=2,
        sector_name="Test Sector",
        julian_day="248",
        serial_number="099",
        year=2021,
        uid=2021248099,
        length_km=12.5,
        geometry={"type": "MultiLineString", "coordinates": [[[10.0, 10.0], [11.0, 11.0]]]},
        raw_payload={"secret": "should not leak"},
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    rows = list_pfz_zones()

    matching = [r for r in rows if r["external_id"] == "service-test-1"]
    assert len(matching) == 1
    assert matching[0]["sector_name"] == "Test Sector"
    assert matching[0]["geometry"] == zone.geometry
    assert "raw_payload" not in matching[0]
