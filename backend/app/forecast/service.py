"""Cache-with-TTL for multi-day forecast queries, mirroring
app/weather/service.py's pattern for current-conditions queries — same
freshness window, same point-location live-fallback exception (spec §3's
amendment), different shape (one row per forecast day instead of one row
per coordinate).
"""

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import WeatherForecast
from app.providers.open_meteo import OpenMeteoWeatherProvider
from app.providers.weather import WeatherProvider

logger = logging.getLogger(__name__)

_FRESHNESS_WINDOW = timedelta(minutes=20)
_COORDINATE_PRECISION = 2

_RESPONSE_FIELDS = (
    "latitude",
    "longitude",
    "forecast_date",
    "weather_code",
    "temp_max_c",
    "temp_min_c",
    "precip_probability_pct",
    "precip_sum_mm",
    "wind_speed_max_kmh",
    "fetched_at",
)

_MUTABLE_COLUMNS = (
    "weather_code",
    "temp_max_c",
    "temp_min_c",
    "precip_probability_pct",
    "precip_sum_mm",
    "wind_speed_max_kmh",
    "raw_payload",
    "fetched_at",
)


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def get_forecast(
    latitude: float, longitude: float, days: int = 5, provider: WeatherProvider | None = None
) -> list[dict]:
    rounded_lat = round(latitude, _COORDINATE_PRECISION)
    rounded_lon = round(longitude, _COORDINATE_PRECISION)

    engine = get_engine()

    with engine.connect() as conn:
        rows = (
            conn.execute(
                select(WeatherForecast)
                .where(
                    WeatherForecast.latitude == rounded_lat,
                    WeatherForecast.longitude == rounded_lon,
                )
                .order_by(WeatherForecast.forecast_date)
            )
            .mappings()
            .all()
        )

    now = datetime.now(timezone.utc)
    # A cached batch is treated as fresh only if there are enough rows to
    # answer this request AND the freshest of them is still within the
    # window — a stale or partial cache falls through to a live re-fetch,
    # same as every other cache-with-TTL service in this codebase.
    if len(rows) >= days and rows and (now - max(r["fetched_at"] for r in rows)) < _FRESHNESS_WINDOW:
        return [_to_response(row) for row in rows[:days]]

    try:
        forecast_days = (provider or OpenMeteoWeatherProvider()).fetch_forecast(
            rounded_lat, rounded_lon, days
        )
    except Exception:
        if rows:
            logger.warning(
                "Live forecast fetch failed for (%s, %s); serving stale cache "
                "from %s",
                rounded_lat,
                rounded_lon,
                max(r["fetched_at"] for r in rows),
            )
            return [_to_response(row) for row in rows[:days]]
        raise

    fetched_at = datetime.now(timezone.utc)
    updated_rows = []

    with engine.begin() as conn:
        for day in forecast_days:
            stmt = pg_insert(WeatherForecast).values(
                latitude=rounded_lat,
                longitude=rounded_lon,
                forecast_date=day.forecast_date,
                weather_code=day.weather_code,
                temp_max_c=day.temp_max_c,
                temp_min_c=day.temp_min_c,
                precip_probability_pct=day.precip_probability_pct,
                precip_sum_mm=day.precip_sum_mm,
                wind_speed_max_kmh=day.wind_speed_max_kmh,
                raw_payload=day.raw_payload,
                fetched_at=fetched_at,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[
                    WeatherForecast.latitude,
                    WeatherForecast.longitude,
                    WeatherForecast.forecast_date,
                ],
                set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
            ).returning(WeatherForecast)
            updated_rows.append(conn.execute(stmt).mappings().one())

    return [_to_response(row) for row in updated_rows]
