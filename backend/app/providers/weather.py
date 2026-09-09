from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class WeatherReadingData:
    latitude: float
    longitude: float
    temperature_c: float
    humidity_pct: float
    weather_code: int
    wind_speed_kmh: float
    wind_direction_deg: float
    observed_at: str
    timezone: str
    raw_payload: dict[str, Any]

    # Nullable by design. Open-Meteo omits these for some points, and a
    # missing value must stay None rather than becoming 0 — a "0 hPa" or a
    # "0°" feels-like reads as a real measurement in the UI.
    apparent_temperature_c: float | None = None
    pressure_hpa: float | None = None
    dew_point_c: float | None = None

    # Hourly series: [{"time": str, "temperature_c": float,
    # "weather_code": int}, ...], oldest first, exactly as upstream
    # ordered it. Trimming to a display window is the service's job.
    hourly: list[dict[str, Any]] | None = None


@dataclass
class ForecastDayData:
    latitude: float
    longitude: float
    forecast_date: str
    weather_code: int
    temp_max_c: float
    temp_min_c: float
    precip_probability_pct: float | None
    precip_sum_mm: float
    wind_speed_max_kmh: float
    raw_payload: dict[str, Any]

    # Nullable, as above. Sun times stay upstream ISO strings, like
    # forecast_date already does — the frontend formats for display.
    uv_index_max: float | None = None
    sunrise: str | None = None
    sunset: str | None = None


class WeatherProvider(Protocol):
    def fetch_current(self, latitude: float, longitude: float) -> WeatherReadingData: ...
    def fetch_forecast(self, latitude: float, longitude: float, days: int) -> list[ForecastDayData]: ...
