"""Live-fallback cache for point-location weather queries.

This is the narrow, spec-amended exception to WeatherGPT's default
ingestion/query split: Open-Meteo has no bounded location set to
precompute, so this module checks Postgres first and calls the provider
live only on a cache miss or stale row (see spec section 3's amendment).
Broadcast feeds with a bounded location set (e.g. SACHET alerts) use
scheduled ingestion instead — see app/ingestion/. A third pattern,
permanent caching with no TTL at all, is used where the upstream is
rate-constrained rather than generous — see app/geocoding/service.py.
This cache-with-TTL pattern is reusable, not a one-off: app/aviation/
service.py follows the same shape for a second generously-rate-limited,
point-queried source.
"""

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import WeatherReading
from app.providers.open_meteo import OpenMeteoWeatherProvider
from app.providers.weather import WeatherProvider

logger = logging.getLogger(__name__)

_FRESHNESS_WINDOW = timedelta(minutes=20)
_COORDINATE_PRECISION = 2

_RESPONSE_FIELDS = (
    "latitude",
    "longitude",
    "temperature_c",
    "humidity_pct",
    "weather_code",
    "wind_speed_kmh",
    "wind_direction_deg",
    "observed_at",
    "timezone",
    "fetched_at",
)

_MUTABLE_COLUMNS = (
    "temperature_c",
    "humidity_pct",
    "weather_code",
    "wind_speed_kmh",
    "wind_direction_deg",
    "observed_at",
    "timezone",
    "raw_payload",
    "fetched_at",
)


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def get_weather(
    latitude: float, longitude: float, provider: WeatherProvider | None = None
) -> dict:
    rounded_lat = round(latitude, _COORDINATE_PRECISION)
    rounded_lon = round(longitude, _COORDINATE_PRECISION)

    engine = get_engine()

    with engine.connect() as conn:
        row = (
            conn.execute(
                select(WeatherReading).where(
                    WeatherReading.latitude == rounded_lat,
                    WeatherReading.longitude == rounded_lon,
                )
            )
            .mappings()
            .first()
        )

    now = datetime.now(timezone.utc)
    if row is not None and (now - row["fetched_at"]) < _FRESHNESS_WINDOW:
        return _to_response(row)

    try:
        reading = (provider or OpenMeteoWeatherProvider()).fetch_current(
            rounded_lat, rounded_lon
        )
    except Exception:
        if row is not None:
            logger.warning(
                "Live weather fetch failed for (%s, %s); serving stale cache "
                "from %s",
                rounded_lat,
                rounded_lon,
                row["fetched_at"],
            )
            return _to_response(row)
        raise

    fetched_at = datetime.now(timezone.utc)

    with engine.begin() as conn:
        stmt = pg_insert(WeatherReading).values(
            latitude=rounded_lat,
            longitude=rounded_lon,
            temperature_c=reading.temperature_c,
            humidity_pct=reading.humidity_pct,
            weather_code=reading.weather_code,
            wind_speed_kmh=reading.wind_speed_kmh,
            wind_direction_deg=reading.wind_direction_deg,
            observed_at=reading.observed_at,
            timezone=reading.timezone,
            raw_payload=reading.raw_payload,
            fetched_at=fetched_at,
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=[WeatherReading.latitude, WeatherReading.longitude],
            set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
        ).returning(WeatherReading)
        updated_row = conn.execute(stmt).mappings().one()

    return _to_response(updated_row)
