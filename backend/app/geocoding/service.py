"""Permanent cache for geocoding lookups.

Place names don't move — unlike weather (see app/weather/service.py's
cache-with-TTL pattern), a geocode result is cached forever once found,
with no freshness check. This also respects Nominatim's usage policy,
which requires client-side caching and caps regular/scripted use at 4
requests/minute; see spec section 3's amendments.
"""

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.engine import Engine

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


def _to_response(row) -> dict | None:
    if row is None:
        return None
    return {field: row[field] for field in _RESPONSE_FIELDS}


def _read_cached(engine: Engine, normalized_query: str):
    with engine.connect() as conn:
        return (
            conn.execute(
                select(GeocodeCache).where(GeocodeCache.query == normalized_query)
            )
            .mappings()
            .first()
        )


def geocode_place(
    query: str, provider: GeocodingProvider | None = None
) -> dict | None:
    normalized_query = query.strip().lower()

    engine = get_engine()

    row = _read_cached(engine, normalized_query)
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
    return _to_response(_read_cached(engine, normalized_query))


# Reverse lookups are cached under a ROUNDED coordinate, not the raw one.
# Two decimal places is ~1.1km — far finer than the city-level name being
# looked up, but coarse enough that a phone's GPS jitter does not trigger
# a fresh Nominatim call on every refresh. Their usage policy caps
# scripted use at ~4 requests/minute, so this matters.
_REVERSE_PRECISION = 2


def _reverse_cache_key(latitude: float, longitude: float) -> str:
    # The "@" prefix keeps reverse entries from ever colliding with a
    # forward query, which is a user-typed place name.
    lat = round(latitude, _REVERSE_PRECISION)
    lon = round(longitude, _REVERSE_PRECISION)
    return f"@{lat},{lon}"


def reverse_geocode_point(
    latitude: float, longitude: float, provider: GeocodingProvider | None = None
) -> dict | None:
    """Name a coordinate, cached permanently like a forward lookup.

    Returns None when Nominatim has no match — an ocean coordinate has no
    place name, and that is a legitimate answer rather than an error.
    """
    cache_key = _reverse_cache_key(latitude, longitude)

    engine = get_engine()

    row = _read_cached(engine, cache_key)
    if row is not None:
        return _to_response(row)

    result = (provider or NominatimGeocodingProvider()).reverse(latitude, longitude)
    if result is None:
        return None

    fetched_at = datetime.now(timezone.utc)

    with engine.begin() as conn:
        stmt = pg_insert(GeocodeCache).values(
            query=cache_key,
            display_name=result.display_name,
            # The caller's own coordinates, so weather is fetched for
            # where the user is rather than a district centroid.
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

    return _to_response(_read_cached(engine, cache_key))
