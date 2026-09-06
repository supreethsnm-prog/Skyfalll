import httpx

from app.providers.geocoding import GeocodeResultData

NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org/search"
_USER_AGENT = "WeatherGPT/0.1 (SIH 2026 hackathon project)"


class NominatimGeocodingProvider:
    def __init__(self, base_url: str = NOMINATIM_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def geocode(self, query: str) -> GeocodeResultData | None:
        try:
            response = self._client.get(
                self._base_url,
                params={
                    "q": query,
                    "format": "jsonv2",
                    "limit": 1,
                    "addressdetails": 1,
                },
                headers={"User-Agent": _USER_AGENT},
            )
            response.raise_for_status()
            results = response.json()
            if not results:
                return None

            result = results[0]
            address = result.get("address", {})
            return GeocodeResultData(
                query=query,
                display_name=result["display_name"],
                latitude=float(result["lat"]),
                longitude=float(result["lon"]),
                country=address.get("country"),
                state=address.get("state"),
                raw_payload=result,
            )
        finally:
            if self._owns_client:
                self._client.close()
