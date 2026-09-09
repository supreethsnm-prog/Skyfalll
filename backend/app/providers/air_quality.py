from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class AirQualityData:
    """One air-quality observation for a point.

    Every pollutant field is nullable: Open-Meteo's air-quality model has
    sparser coverage than its weather model, and a missing reading must
    stay None rather than becoming 0 — an "AQI 0" would read as pristine
    air rather than as no data.
    """

    latitude: float
    longitude: float
    observed_at: str
    raw_payload: dict[str, Any]

    # US EPA AQI. Chosen over european_aqi because the 0-500 US scale and
    # its band names ("Unhealthy", "Hazardous") are what Indian AQI
    # reporting and the public are familiar with.
    us_aqi: float | None = None
    pm2_5: float | None = None
    pm10: float | None = None


class AirQualityProvider(Protocol):
    def fetch_current(self, latitude: float, longitude: float) -> AirQualityData: ...
