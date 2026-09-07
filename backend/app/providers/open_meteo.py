import logging

import httpx

from app.providers.weather import ForecastDayData, WeatherReadingData

logger = logging.getLogger(__name__)

OPEN_METEO_BASE_URL = "https://api.open-meteo.com/v1/forecast"
_CURRENT_FIELDS = (
    "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m"
)
_DAILY_FIELDS = (
    "weather_code,temperature_2m_max,temperature_2m_min,"
    "precipitation_probability_max,precipitation_sum,wind_speed_10m_max"
)


class OpenMeteoWeatherProvider:
    def __init__(self, base_url: str = OPEN_METEO_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def fetch_current(self, latitude: float, longitude: float) -> WeatherReadingData:
        try:
            response = self._client.get(
                self._base_url,
                params={
                    "latitude": latitude,
                    "longitude": longitude,
                    "current": _CURRENT_FIELDS,
                    "timezone": "auto",
                },
            )
            response.raise_for_status()
            payload = response.json()
            try:
                current = payload["current"]
                return WeatherReadingData(
                    latitude=latitude,
                    longitude=longitude,
                    temperature_c=current["temperature_2m"],
                    humidity_pct=current["relative_humidity_2m"],
                    weather_code=current["weather_code"],
                    wind_speed_kmh=current["wind_speed_10m"],
                    wind_direction_deg=current["wind_direction_10m"],
                    observed_at=current["time"],
                    timezone=payload["timezone"],
                    raw_payload=payload,
                )
            except (KeyError, TypeError) as exc:
                logger.warning(
                    "Failed to parse Open-Meteo response for (%s, %s): %s",
                    latitude,
                    longitude,
                    exc,
                )
                raise
        finally:
            if self._owns_client:
                self._client.close()

    def fetch_forecast(self, latitude: float, longitude: float, days: int = 7) -> list[ForecastDayData]:
        try:
            response = self._client.get(
                self._base_url,
                params={
                    "latitude": latitude,
                    "longitude": longitude,
                    "daily": _DAILY_FIELDS,
                    "timezone": "auto",
                    "forecast_days": days,
                },
            )
            response.raise_for_status()
            payload = response.json()
            try:
                daily = payload["daily"]
                return [
                    ForecastDayData(
                        latitude=latitude,
                        longitude=longitude,
                        forecast_date=daily["time"][i],
                        weather_code=daily["weather_code"][i],
                        temp_max_c=daily["temperature_2m_max"][i],
                        temp_min_c=daily["temperature_2m_min"][i],
                        precip_probability_pct=daily["precipitation_probability_max"][i],
                        precip_sum_mm=daily["precipitation_sum"][i],
                        wind_speed_max_kmh=daily["wind_speed_10m_max"][i],
                        raw_payload=payload,
                    )
                    for i in range(len(daily["time"]))
                ]
            except (KeyError, IndexError, TypeError) as exc:
                logger.warning(
                    "Failed to parse Open-Meteo forecast response for (%s, %s): %s",
                    latitude,
                    longitude,
                    exc,
                )
                raise
        finally:
            if self._owns_client:
                self._client.close()
