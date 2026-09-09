import logging

import httpx

from app.providers.air_quality import AirQualityData

logger = logging.getLogger(__name__)

# A different host from the weather endpoint, but the same free service
# with no API key. Kept in its own provider rather than folded into
# OpenMeteoWeatherProvider because it is a separate upstream with its own
# availability and its own cache freshness.
OPEN_METEO_AIR_QUALITY_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"

_CURRENT_FIELDS = "us_aqi,pm2_5,pm10"


class OpenMeteoAirQualityProvider:
    """Mirrors OpenMeteoWeatherProvider's shape exactly: an injectable
    client for tests, a module-level field tuple, a dataclass out, and the
    raw payload retained."""

    def __init__(
        self,
        base_url: str = OPEN_METEO_AIR_QUALITY_URL,
        client: httpx.Client | None = None,
    ):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def fetch_current(self, latitude: float, longitude: float) -> AirQualityData:
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
                return AirQualityData(
                    # The caller's coordinates, not Open-Meteo's snapped
                    # grid point — the cache is keyed on what was asked for.
                    latitude=latitude,
                    longitude=longitude,
                    observed_at=current["time"],
                    raw_payload=payload,
                    # .get(): the air-quality model has sparser coverage
                    # than the weather model, so absent pollutants are
                    # normal and must not fail the fetch.
                    us_aqi=current.get("us_aqi"),
                    pm2_5=current.get("pm2_5"),
                    pm10=current.get("pm10"),
                )
            except (KeyError, TypeError) as exc:
                logger.warning(
                    "Failed to parse Open-Meteo air-quality response for (%s, %s): %s",
                    latitude,
                    longitude,
                    exc,
                )
                raise
        finally:
            if self._owns_client:
                self._client.close()
