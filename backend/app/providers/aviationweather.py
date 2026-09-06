import httpx

from app.providers.aviation import MetarReadingData

AVIATIONWEATHER_BASE_URL = "https://aviationweather.gov/api/data/metar"


def _safe_float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


class AviationWeatherGovProvider:
    def __init__(self, base_url: str = AVIATIONWEATHER_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def fetch_metar(self, icao_id: str) -> MetarReadingData | None:
        try:
            response = self._client.get(
                self._base_url,
                params={"ids": icao_id, "format": "json"},
            )
            if response.status_code == 204 or not response.text:
                return None
            response.raise_for_status()
            results = response.json()
            if not results:
                return None

            result = results[0]
            return MetarReadingData(
                icao_id=result["icaoId"],
                raw_metar=result["rawOb"],
                observed_at=result["reportTime"],
                temperature_c=_safe_float(result.get("temp")),
                dewpoint_c=_safe_float(result.get("dewp")),
                wind_dir_deg=_safe_float(result.get("wdir")),
                wind_speed_kt=_safe_float(result.get("wspd")),
                visibility_sm=_safe_float(result.get("visib")),
                flight_category=result.get("fltCat"),
                station_name=result.get("name"),
                latitude=_safe_float(result.get("lat")),
                longitude=_safe_float(result.get("lon")),
                raw_payload=result,
            )
        finally:
            if self._owns_client:
                self._client.close()
