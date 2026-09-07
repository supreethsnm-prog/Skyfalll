from app.ingestion.marine import ingest_pfz_zones
from app.marine.service import list_pfz_zones
from app.providers.marine import PfzZoneData
from tests.conftest import _FakeMarineProvider


def _zone(external_id: str, geometry: dict) -> PfzZoneData:
    return PfzZoneData(
        external_id=external_id, category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry=geometry, raw_payload={},
    )


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


def test_list_pfz_zones_with_no_location_returns_everything_unfiltered(clean_pfz_zones):
    # GeoJSON coordinate order is [longitude, latitude] — verified live
    # against real INCOIS data during planning (see the plan doc). Getting
    # this backwards would silently compute wrong-but-plausible distances,
    # since India's longitude (~68-98) and latitude (~6-38) ranges don't
    # overlap, so a swap fails silently rather than crashing.
    near = _zone("near-1", {"type": "MultiLineString", "coordinates": [[[72.88, 19.06], [72.90, 19.08]]]})
    far = _zone("far-1", {"type": "MultiLineString", "coordinates": [[[77.2, 28.6], [77.3, 28.7]]]})
    ingest_pfz_zones(_FakeMarineProvider([near, far]))

    rows = list_pfz_zones()

    assert {r["external_id"] for r in rows} == {"near-1", "far-1"}


def test_list_pfz_zones_filters_by_centroid_distance(clean_pfz_zones):
    near = _zone("near-1", {"type": "MultiLineString", "coordinates": [[[72.88, 19.06], [72.90, 19.08]]]})
    far = _zone("far-1", {"type": "MultiLineString", "coordinates": [[[77.2, 28.6], [77.3, 28.7]]]})
    ingest_pfz_zones(_FakeMarineProvider([near, far]))

    rows = list_pfz_zones(latitude=19.05, longitude=72.87, radius_km=200.0)

    assert [r["external_id"] for r in rows] == ["near-1"]
    assert "distance_km" in rows[0]


def test_list_pfz_zones_centroid_averages_all_points_across_all_lines(clean_pfz_zones):
    # A MultiLineString can have more than one line; the centroid must
    # average every point across every line, not just the first line.
    zone = _zone(
        "multi-line-1",
        {
            "type": "MultiLineString",
            "coordinates": [
                [[72.80, 19.00], [72.82, 19.02]],
                [[72.96, 19.10], [72.98, 19.12]],
            ],
        },
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    # The true centroid of all 4 points is close to (72.89, 19.06); a query
    # point right at that centroid should find it well within a tight radius,
    # proving all 4 points (not just the first line's 2) were averaged.
    rows = list_pfz_zones(latitude=19.06, longitude=72.89, radius_km=5.0)

    assert [r["external_id"] for r in rows] == ["multi-line-1"]


def test_list_pfz_zones_skips_malformed_geometry_without_aborting_the_batch(clean_pfz_zones):
    # An empty MultiLineString's coordinates list makes _centroid's averaging
    # divide by zero (count == 0); this must not abort the whole filtered
    # query — just that one zone should be skipped.
    well_formed = _zone(
        "near-1", {"type": "MultiLineString", "coordinates": [[[72.88, 19.06], [72.90, 19.08]]]}
    )
    malformed = _zone("malformed-1", {"type": "MultiLineString", "coordinates": []})
    ingest_pfz_zones(_FakeMarineProvider([well_formed, malformed]))

    rows = list_pfz_zones(latitude=19.05, longitude=72.87, radius_km=200.0)

    assert [r["external_id"] for r in rows] == ["near-1"]


def test_list_pfz_zones_with_only_latitude_returns_everything_unfiltered(clean_pfz_zones):
    near = _zone("near-1", {"type": "MultiLineString", "coordinates": [[[72.88, 19.06], [72.90, 19.08]]]})
    far = _zone("far-1", {"type": "MultiLineString", "coordinates": [[[77.2, 28.6], [77.3, 28.7]]]})
    ingest_pfz_zones(_FakeMarineProvider([near, far]))

    rows = list_pfz_zones(latitude=19.05)

    assert {r["external_id"] for r in rows} == {"near-1", "far-1"}
