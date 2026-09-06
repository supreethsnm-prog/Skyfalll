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


class WeatherProvider(Protocol):
    def fetch_current(self, latitude: float, longitude: float) -> WeatherReadingData: ...
