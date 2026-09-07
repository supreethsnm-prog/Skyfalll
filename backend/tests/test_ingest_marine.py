from sqlalchemy import select

from app.db import get_engine
from app.ingestion.marine import ingest_pfz_zones
from app.models import PfzZone
from app.providers.marine import PfzZoneData
from tests.conftest import _FakeMarineProvider


def _sample_zone(sector_name: str = "West Coast") -> PfzZoneData:
    return PfzZoneData(
        external_id="pfzlines.1",
        category="ghrsst",
        sector_boundary=2,
        sector_name=sector_name,
        julian_day="248",
        serial_number="001",
        year=2021,
        uid=2021248001,
        length_km=45.99,
        geometry={"type": "MultiLineString", "coordinates": [[[68.4, 22.7], [68.5, 22.8]]]},
        raw_payload={"id": "pfzlines.1"},
    )


def test_ingest_pfz_zones_inserts_new_zone(clean_pfz_zones):
    count = ingest_pfz_zones(_FakeMarineProvider([_sample_zone()]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(PfzZone).where(PfzZone.external_id == "pfzlines.1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].sector_name == "West Coast"


def test_ingest_pfz_zones_upserts_existing_zone_by_external_id(clean_pfz_zones):
    ingest_pfz_zones(_FakeMarineProvider([_sample_zone(sector_name="West Coast")]))
    count = ingest_pfz_zones(_FakeMarineProvider([_sample_zone(sector_name="East Coast")]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(PfzZone).where(PfzZone.external_id == "pfzlines.1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].sector_name == "East Coast"


def test_ingest_pfz_zones_removes_zones_absent_from_the_latest_fetch(clean_pfz_zones):
    stale_zone = PfzZoneData(
        external_id="old-zone-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[72.8, 19.0], [72.9, 19.1]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([stale_zone]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    assert len(rows) == 1

    current_zone = PfzZoneData(
        external_id="current-zone-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[73.0, 19.2], [73.1, 19.3]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([current_zone]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    assert {r["external_id"] for r in rows} == {"current-zone-1"}


def test_ingest_pfz_zones_keeps_zones_still_present_in_the_latest_fetch(clean_pfz_zones):
    zone = PfzZoneData(
        external_id="persistent-zone-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[72.8, 19.0], [72.9, 19.1]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "persistent-zone-1"


def test_ingest_pfz_zones_does_not_wipe_existing_rows_on_an_empty_fetch(clean_pfz_zones):
    zone = PfzZoneData(
        external_id="keep-me-zone-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[72.8, 19.0], [72.9, 19.1]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    count = ingest_pfz_zones(_FakeMarineProvider([]))

    assert count == 0
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "keep-me-zone-1"
