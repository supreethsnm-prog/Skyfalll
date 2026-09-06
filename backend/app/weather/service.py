from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import WeatherReading
from app.providers.open_meteo import OpenMeteoWeatherProvider
from app.providers.weather import WeatherProvider

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


def get_weather(
    latitude: float, longitude: float, provider: WeatherProvider | None = None
) -> dict:
    rounded_lat = round(latitude, _COORDINATE_PRECISION)
    rounded_lon = round(longitude, _COORDINATE_PRECISION)

    engine = get_engine()
    now = datetime.now(timezone.utc)

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

    if row is not None and (now - row["fetched_at"]) < _FRESHNESS_WINDOW:
        return {field: row[field] for field in _RESPONSE_FIELDS}

    reading = (provider or OpenMeteoWeatherProvider()).fetch_current(
        rounded_lat, rounded_lon
    )

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
            fetched_at=now,
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=[WeatherReading.latitude, WeatherReading.longitude],
            set_={
                "temperature_c": stmt.excluded.temperature_c,
                "humidity_pct": stmt.excluded.humidity_pct,
                "weather_code": stmt.excluded.weather_code,
                "wind_speed_kmh": stmt.excluded.wind_speed_kmh,
                "wind_direction_deg": stmt.excluded.wind_direction_deg,
                "observed_at": stmt.excluded.observed_at,
                "timezone": stmt.excluded.timezone,
                "raw_payload": stmt.excluded.raw_payload,
                "fetched_at": stmt.excluded.fetched_at,
            },
        )
        conn.execute(stmt)

    return {
        "latitude": rounded_lat,
        "longitude": rounded_lon,
        "temperature_c": reading.temperature_c,
        "humidity_pct": reading.humidity_pct,
        "weather_code": reading.weather_code,
        "wind_speed_kmh": reading.wind_speed_kmh,
        "wind_direction_deg": reading.wind_direction_deg,
        "observed_at": reading.observed_at,
        "timezone": reading.timezone,
        "fetched_at": now,
    }
