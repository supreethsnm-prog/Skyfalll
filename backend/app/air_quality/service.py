"""Live-fallback cache for point-location air-quality queries.

Follows the same cache-with-TTL shape as app/weather/service.py and
app/aviation/service.py: check Postgres, serve the row if it is inside the
freshness window, otherwise fetch live and upsert. See app/weather/
service.py's module docstring for why this pattern (rather than scheduled
ingestion) is the right one for a point-queried, generously-rate-limited
upstream with no bounded location set.
"""

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import AirQualityReading
from app.providers.air_quality import AirQualityProvider
from app.providers.open_meteo_air_quality import OpenMeteoAirQualityProvider

logger = logging.getLogger(__name__)

# Deliberately longer than weather's 20 minutes: air quality moves far more
# slowly than temperature, and this upstream is the more rate-limited of
# the two.
_FRESHNESS_WINDOW = timedelta(minutes=60)
_COORDINATE_PRECISION = 2

_RESPONSE_FIELDS = (
    "latitude",
    "longitude",
    "us_aqi",
    "pm2_5",
    "pm10",
    "observed_at",
    "fetched_at",
)

_MUTABLE_COLUMNS = (
    "us_aqi",
    "pm2_5",
    "pm10",
    "observed_at",
    "raw_payload",
    "fetched_at",
)


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def get_air_quality(
    latitude: float, longitude: float, provider: AirQualityProvider | None = None
) -> dict:
    rounded_lat = round(latitude, _COORDINATE_PRECISION)
    rounded_lon = round(longitude, _COORDINATE_PRECISION)

    engine = get_engine()

    with engine.connect() as conn:
        row = (
            conn.execute(
                select(AirQualityReading).where(
                    AirQualityReading.latitude == rounded_lat,
                    AirQualityReading.longitude == rounded_lon,
                )
            )
            .mappings()
            .first()
        )

    now = datetime.now(timezone.utc)
    if row is not None and (now - row["fetched_at"]) < _FRESHNESS_WINDOW:
        return _to_response(row)

    try:
        reading = (provider or OpenMeteoAirQualityProvider()).fetch_current(
            rounded_lat, rounded_lon
        )
    except Exception:
        if row is not None:
            logger.warning(
                "Live air-quality fetch failed for (%s, %s); serving stale "
                "cache from %s",
                rounded_lat,
                rounded_lon,
                row["fetched_at"],
            )
            return _to_response(row)
        raise

    fetched_at = datetime.now(timezone.utc)

    with engine.begin() as conn:
        stmt = pg_insert(AirQualityReading).values(
            latitude=rounded_lat,
            longitude=rounded_lon,
            observed_at=reading.observed_at,
            raw_payload=reading.raw_payload,
            fetched_at=fetched_at,
            us_aqi=reading.us_aqi,
            pm2_5=reading.pm2_5,
            pm10=reading.pm10,
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=[AirQualityReading.latitude, AirQualityReading.longitude],
            set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
        ).returning(AirQualityReading)
        updated_row = conn.execute(stmt).mappings().one()

    return _to_response(updated_row)
