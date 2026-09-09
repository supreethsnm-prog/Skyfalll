import logging

import httpx

from app.providers.weather import ForecastDayData, WeatherReadingData

logger = logging.getLogger(__name__)

OPEN_METEO_BASE_URL = "https://api.open-meteo.com/v1/forecast"
_CURRENT_FIELDS = (
    "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,"
    "wind_direction_10m,apparent_temperature,pressure_msl,dew_point_2m"
)
_HOURLY_FIELDS = "temperature_2m,weather_code"
_DAILY_FIELDS = (
    "weather_code,temperature_2m_max,temperature_2m_min,"
    "precipitation_probability_max,precipitation_sum,wind_speed_10m_max,"
    "uv_index_max,sunrise,sunset"
)

# Two days of hourly data, so there is always a full 24 hours ahead of the
# current hour regardless of what time of day the request lands.
_HOURLY_FORECAST_DAYS = 2


def _daily_at(daily: dict, field: str, index: int):
    """One optional daily value, or None if the field or index is missing.

    Kept separate from the required fields' `daily[...][i]` indexing so a
    supplementary field can be absent without failing the whole forecast.
    """
    values = daily.get(field)
    if not isinstance(values, list) or index >= len(values):
        return None
    return values[index]


def _zip_hourly(payload: dict) -> list[dict] | None:
    """Turn Open-Meteo's parallel hourly arrays into one record per hour.

    Returns None when the block is absent or malformed rather than raising:
    the hourly strip is supplementary, and losing it should never fail a
    current-conditions fetch that otherwise succeeded.
    """
    hourly = payload.get("hourly")
    if not isinstance(hourly, dict):
        return None

    times = hourly.get("time")
    temps = hourly.get("temperature_2m")
    codes = hourly.get("weather_code")
    if not times or temps is None or codes is None:
        return None

    return [
        {"time": times[i], "temperature_c": temps[i], "weather_code": codes[i]}
        for i in range(min(len(times), len(temps), len(codes)))
    ]


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
                    "hourly": _HOURLY_FIELDS,
                    "forecast_days": _HOURLY_FORECAST_DAYS,
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
                    # .get(), not [], so a point where Open-Meteo omits
                    # these yields None instead of failing the whole fetch.
                    apparent_temperature_c=current.get("apparent_temperature"),
                    pressure_hpa=current.get("pressure_msl"),
                    dew_point_c=current.get("dew_point_2m"),
                    hourly=_zip_hourly(payload),
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
                        # Absent for some points; a missing array and a
                        # short array both degrade to None rather than
                        # raising, since these are supplementary.
                        uv_index_max=_daily_at(daily, "uv_index_max", i),
                        sunrise=_daily_at(daily, "sunrise", i),
                        sunset=_daily_at(daily, "sunset", i),
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
