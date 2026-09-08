"""Query-path read of the latest ingested GFS grid (app/ingestion/gfs.py
populates this table on a scheduled cycle — see that module's docstring
for why reconciliation here works differently from every other
scheduled-broadcast source in this codebase).

Snapping an arbitrary real-world coordinate to the nearest actual 0.25-
degree grid point is exact, not an approximation: GFS's 0.25-degree grid
is perfectly regular, so round(x * 4) / 4 always lands on a real grid
node. No live provider call ever happens here — a query-time miss (the
coordinate is outside India's bounding box, or nothing has been ingested
yet) returns an empty list, never a live GFS fetch (unlike
app/weather/service.py's Open-Meteo point-lookup, GFS is not a
generously-rate-limited, arbitrary-point-queryable source — see this
plan's spec).
"""

from sqlalchemy import select

from app.db import get_engine
from app.models import GfsForecastPoint

_INDIA_LAT_RANGE = (6.0, 38.0)
_INDIA_LON_RANGE = (68.0, 98.0)

_RESPONSE_FIELDS = (
    "run_date", "run_hour", "forecast_hour", "valid_time",
    "temp_2m_c", "relative_humidity_2m_pct", "wind_speed_10m_kmh",
    "wind_direction_10m_deg", "wind_gust_kmh", "precip_rate_mmh",
    "cape_j_per_kg", "cin_j_per_kg", "cloud_cover_pct", "mslp_hpa",
)


def _snap_to_grid(value: float) -> float:
    return round(value * 4) / 4


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def get_nwp_forecast(
    latitude: float, longitude: float, forecast_hours: list[int] | None = None
) -> list[dict]:
    if not (_INDIA_LAT_RANGE[0] <= latitude <= _INDIA_LAT_RANGE[1]):
        return []
    if not (_INDIA_LON_RANGE[0] <= longitude <= _INDIA_LON_RANGE[1]):
        return []

    grid_lat = _snap_to_grid(latitude)
    grid_lon = _snap_to_grid(longitude)

    query = select(GfsForecastPoint).where(
        GfsForecastPoint.grid_latitude == grid_lat,
        GfsForecastPoint.grid_longitude == grid_lon,
    )
    if forecast_hours is not None:
        query = query.where(GfsForecastPoint.forecast_hour.in_(forecast_hours))
    query = query.order_by(GfsForecastPoint.forecast_hour)

    with get_engine().connect() as conn:
        rows = conn.execute(query).mappings().all()

    return [_to_response(row) for row in rows]
