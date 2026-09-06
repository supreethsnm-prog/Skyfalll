"""Scheduled ingestion for INCOIS's bounded PFZ (Potential Fishing Zone)
feature collection — same pattern as app/ingestion/alerts.py: fetch the
whole collection and upsert every row, keyed on a stable external id.
Not a per-query cache — see app/weather/service.py (cache-with-TTL) and
app/geocoding/service.py (permanent cache) for the two point-query
patterns used elsewhere in this codebase.
"""

from datetime import datetime, timezone

from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import PfzZone
from app.providers.marine import MarineProvider

_IMMUTABLE_COLUMNS = {"id", "external_id"}
_UPSERT_COLUMNS = tuple(
    col.name for col in PfzZone.__table__.columns if col.name not in _IMMUTABLE_COLUMNS
)


def ingest_pfz_zones(provider: MarineProvider) -> int:
    zones = provider.fetch_pfz_zones()
    if not zones:
        return 0

    fetched_at = datetime.now(timezone.utc)
    with get_engine().begin() as conn:
        for zone in zones:
            stmt = pg_insert(PfzZone).values(
                external_id=zone.external_id,
                category=zone.category,
                sector_boundary=zone.sector_boundary,
                sector_name=zone.sector_name,
                julian_day=zone.julian_day,
                serial_number=zone.serial_number,
                year=zone.year,
                uid=zone.uid,
                length_km=zone.length_km,
                geometry=zone.geometry,
                raw_payload=zone.raw_payload,
                fetched_at=fetched_at,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[PfzZone.external_id],
                set_={col: getattr(stmt.excluded, col) for col in _UPSERT_COLUMNS},
            )
            conn.execute(stmt)
    return len(zones)
