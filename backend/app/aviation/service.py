"""Cache-with-TTL for METAR (current airport weather) lookups by ICAO code.

Same pattern as app/weather/service.py: aviationweather.gov is a
point-queried, official, generously-rate-limited source (100 req/min, no
key), so this is the narrow spec-amended exception to WeatherGPT's
default ingestion/query split (see spec section 3's first amendment) —
not the permanent-cache pattern used for geocoding, and not the
scheduled-broadcast pattern used for SACHET alerts.
"""

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.engine import Engine

from app.db import get_engine
from app.models import MetarReading
from app.providers.aviation import AviationWeatherProvider
from app.providers.aviationweather import AviationWeatherGovProvider

logger = logging.getLogger(__name__)

_FRESHNESS_WINDOW = timedelta(minutes=25)

_RESPONSE_FIELDS = (
    "icao_id",
    "raw_metar",
    "observed_at",
    "temperature_c",
    "dewpoint_c",
    "wind_dir_deg",
    "wind_speed_kt",
    "visibility_sm",
    "flight_category",
    "station_name",
    "latitude",
    "longitude",
    "fetched_at",
)

_MUTABLE_COLUMNS = (
    "raw_metar",
    "observed_at",
    "temperature_c",
    "dewpoint_c",
    "wind_dir_deg",
    "wind_speed_kt",
    "visibility_sm",
    "flight_category",
    "station_name",
    "latitude",
    "longitude",
    "raw_payload",
    "fetched_at",
)


def _to_response(row) -> dict | None:
    if row is None:
        return None
    return {field: row[field] for field in _RESPONSE_FIELDS}


def _read_cached(engine: Engine, icao_id: str):
    with engine.connect() as conn:
        return (
            conn.execute(select(MetarReading).where(MetarReading.icao_id == icao_id))
            .mappings()
            .first()
        )


def get_metar(
    icao_id: str, provider: AviationWeatherProvider | None = None
) -> dict | None:
    normalized_icao_id = icao_id.strip().upper()

    engine = get_engine()

    row = _read_cached(engine, normalized_icao_id)

    now = datetime.now(timezone.utc)
    if row is not None and (now - row["fetched_at"]) < _FRESHNESS_WINDOW:
        return _to_response(row)

    try:
        reading = (provider or AviationWeatherGovProvider()).fetch_metar(
            normalized_icao_id
        )
    except Exception:
        if row is not None:
            logger.warning(
                "Live METAR fetch failed for %s; serving stale cache from %s",
                normalized_icao_id,
                row["fetched_at"],
            )
            return _to_response(row)
        raise

    if reading is None:
        # Deliberate: an authoritative "no current observation" (204) is
        # treated as not-found even if a stale row exists, unlike an
        # upstream failure (caught above), which serves the stale row.
        # A silent station outage does not mean the old reading is still
        # a fair representation of current conditions.
        return None

    fetched_at = datetime.now(timezone.utc)

    with engine.begin() as conn:
        stmt = pg_insert(MetarReading).values(
            icao_id=normalized_icao_id,
            raw_metar=reading.raw_metar,
            observed_at=reading.observed_at,
            temperature_c=reading.temperature_c,
            dewpoint_c=reading.dewpoint_c,
            wind_dir_deg=reading.wind_dir_deg,
            wind_speed_kt=reading.wind_speed_kt,
            visibility_sm=reading.visibility_sm,
            flight_category=reading.flight_category,
            station_name=reading.station_name,
            latitude=reading.latitude,
            longitude=reading.longitude,
            raw_payload=reading.raw_payload,
            fetched_at=fetched_at,
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=[MetarReading.icao_id],
            set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
        ).returning(MetarReading)
        updated_row = conn.execute(stmt).mappings().one()

    return _to_response(updated_row)
