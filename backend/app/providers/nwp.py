"""NWPProvider: Numerical Weather Prediction data (spec section 4's "NWP"
requirement, satisfied via GFS). Distinct from WeatherProvider (Open-Meteo,
point-queried, generously rate-limited, live-fallback-on-cache-miss) — GFS
is a bounded, scheduled-broadcast source like SACHET/INCOIS: the whole grid
for the latest model run is fetched on ingestion, never per-request.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol


@dataclass
class GfsGridPointData:
    run_date: str
    run_hour: str
    forecast_hour: int
    valid_time: datetime
    grid_latitude: float
    grid_longitude: float
    temp_2m_c: float | None
    relative_humidity_2m_pct: float | None
    wind_speed_10m_kmh: float | None
    wind_direction_10m_deg: float | None
    wind_gust_kmh: float | None
    precip_rate_mmh: float | None
    cape_j_per_kg: float | None
    cin_j_per_kg: float | None
    cloud_cover_pct: float | None
    mslp_hpa: float | None


class NWPProvider(Protocol):
    def discover_latest_run(self) -> tuple[str, str]: ...

    def fetch_india_grid(
        self, run_date: str, run_hour: str, forecast_hour: int
    ) -> list[GfsGridPointData]: ...
