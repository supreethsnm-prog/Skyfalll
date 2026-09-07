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


class WeatherProvider(Protocol):
    def fetch_current(self, latitude: float, longitude: float) -> WeatherReadingData: ...
    def fetch_forecast(self, latitude: float, longitude: float, days: int) -> list[ForecastDayData]: ...
