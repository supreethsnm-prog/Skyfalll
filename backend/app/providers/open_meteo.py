import httpx

from app.providers.weather import WeatherReadingData

OPEN_METEO_BASE_URL = "https://api.open-meteo.com/v1/forecast"
_CURRENT_FIELDS = (
    "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m"
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
                    "timezone": "Asia/Kolkata",
                },
            )
            response.raise_for_status()
            payload = response.json()
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
        finally:
            if self._owns_client:
                self._client.close()
