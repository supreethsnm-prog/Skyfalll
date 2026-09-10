"""Query-path read of the ERA5 data seeded by
backend/scripts/seed_era5_history.py. This is the only reader of
historical_weather_readings — no live CDS call ever happens here, or
anywhere in the request path (see this plan's Global Constraints).
A miss (an unseeded location/date combination) is an expected, common
outcome given the small fixed seed matrix, not an error.

Note: `precip_mm` is ERA5's 1-hour accumulation ending at the 12:00 UTC
observation time (not a daily total) — see `app/providers/era5.py` for the
underlying request shape.
"""

from sqlalchemy import func, select

from app.db import get_engine
from app.models import HistoricalWeatherReading

_RESPONSE_FIELDS = (
    "location_name", "latitude", "longitude", "observation_date",
    "temp_2m_c", "dewpoint_2m_c", "precip_mm", "wind_speed_10m_kmh",
    "wind_direction_10m_deg", "mslp_hpa",
)


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def get_historical_weather(location_name: str, observation_date: str) -> dict | None:
    with get_engine().connect() as conn:
        row = (
            conn.execute(
                select(HistoricalWeatherReading).where(
                    func.lower(HistoricalWeatherReading.location_name) == location_name.lower(),
                    HistoricalWeatherReading.observation_date == observation_date,
                )
            )
            .mappings()
            .first()
        )

    if row is None:
        return None
    return _to_response(row)


def list_available_history() -> list[dict]:
    """Every (location, date) pair that actually has a reading.

    `get_historical_weather` matches an EXACT location name and date, and
    the seed matrix is small and fixed — so without this a client has no
    way to know what to ask for, and can only guess and collect 404s. That
    made the whole endpoint effectively undiscoverable.

    Grouped by location so a UI can offer a place, then the dates it holds,
    which is the order a person actually chooses in. Dates are sorted
    newest first; ISO-8601 strings sort chronologically as text, so no
    parsing is needed.
    """
    with get_engine().connect() as conn:
        rows = (
            conn.execute(
                select(
                    HistoricalWeatherReading.location_name,
                    HistoricalWeatherReading.observation_date,
                    HistoricalWeatherReading.latitude,
                    HistoricalWeatherReading.longitude,
                ).order_by(
                    HistoricalWeatherReading.location_name,
                    HistoricalWeatherReading.observation_date.desc(),
                )
            )
            .mappings()
            .all()
        )

    grouped: dict[str, dict] = {}
    for row in rows:
        entry = grouped.setdefault(
            row["location_name"],
            {
                "location_name": row["location_name"],
                "latitude": row["latitude"],
                "longitude": row["longitude"],
                "dates": [],
            },
        )
        entry["dates"].append(row["observation_date"])

    return list(grouped.values())
