"""Permanent cache for geocoding lookups.

Place names don't move — unlike weather (see app/weather/service.py's
cache-with-TTL pattern), a geocode result is cached forever once found,
with no freshness check. This also respects Nominatim's usage policy,
which requires client-side caching and caps regular/scripted use at 4
requests/minute; see spec section 3.
"""

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import GeocodeCache
from app.providers.geocoding import GeocodingProvider
from app.providers.nominatim import NominatimGeocodingProvider

_RESPONSE_FIELDS = (
    "query",
    "display_name",
    "latitude",
    "longitude",
    "country",
    "state",
    "fetched_at",
)


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def geocode_place(
    query: str, provider: GeocodingProvider | None = None
) -> dict | None:
    normalized_query = query.strip().lower()

    engine = get_engine()

    with engine.connect() as conn:
        row = (
            conn.execute(
                select(GeocodeCache).where(GeocodeCache.query == normalized_query)
            )
            .mappings()
            .first()
        )

    if row is not None:
        return _to_response(row)

    result = (provider or NominatimGeocodingProvider()).geocode(normalized_query)
    if result is None:
        return None

    fetched_at = datetime.now(timezone.utc)

    with engine.begin() as conn:
        stmt = pg_insert(GeocodeCache).values(
            query=normalized_query,
            display_name=result.display_name,
            latitude=result.latitude,
            longitude=result.longitude,
            country=result.country,
            state=result.state,
            raw_payload=result.raw_payload,
            fetched_at=fetched_at,
        )
        stmt = stmt.on_conflict_do_nothing(
            index_elements=[GeocodeCache.query]
        ).returning(GeocodeCache)
        inserted_row = conn.execute(stmt).mappings().first()

    if inserted_row is not None:
        return _to_response(inserted_row)

    # A concurrent request already inserted this query between our cache
    # check and this insert. Don't overwrite it — re-read what's there.
    with engine.connect() as conn:
        row = (
            conn.execute(
                select(GeocodeCache).where(GeocodeCache.query == normalized_query)
            )
            .mappings()
            .first()
        )
    return _to_response(row)
