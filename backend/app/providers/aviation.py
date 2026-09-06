from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class MetarReadingData:
    icao_id: str
    raw_metar: str
    observed_at: str
    temperature_c: float | None
    dewpoint_c: float | None
    wind_dir_deg: float | None
    wind_speed_kt: float | None
    visibility_sm: float | None
    flight_category: str | None
    station_name: str | None
    latitude: float | None
    longitude: float | None
    raw_payload: dict[str, Any]


class AviationWeatherProvider(Protocol):
    def fetch_metar(self, icao_id: str) -> MetarReadingData | None: ...
