import logging

import httpx

from app.providers.geocoding import GeocodeResultData

NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org/search"
NOMINATIM_REVERSE_URL = "https://nominatim.openstreetmap.org/reverse"
_USER_AGENT = "WeatherGPT/0.1 (SIH 2026 hackathon project)"

# Nominatim returns place names in the LOCAL language by default, so a
# reverse lookup in Nepal came back as "नेपाल" and one in Tamil Nadu would
# come back in Tamil — inconsistent with the rest of the app's English UI,
# and unreadable to a user who does not read that script.
#
# "en" first with a bare quality-ranked fallback: where a place has no
# English exonym, Nominatim falls back to the local name, which is the
# right answer rather than a blank.
_ACCEPT_LANGUAGE = "en"

logger = logging.getLogger(__name__)

# Address keys to try, most specific first, when naming a coordinate.
# Nominatim populates different ones depending on settlement type, and
# rural Indian coordinates often have only `village` or `county`.
_PLACE_KEYS = (
    "city",
    "town",
    "village",
    "suburb",
    "municipality",
    "county",
    "state_district",
    "district",
)


def _short_place_name(address: dict, fallback: str) -> str:
    """A concise "Place, State" label for a coordinate.

    Nominatim's own `display_name` for a reverse lookup is a full postal
    address ("Ward 12, Bhagalpur, Bihar, 812001, India"), which is far too
    long for the Home hero. This picks the most specific settlement name
    available and pairs it with the state.
    """
    place = next(
        (address[key] for key in _PLACE_KEYS if address.get(key)),
        None,
    )
    state = address.get("state")

    if place and state and place != state:
        return f"{place}, {state}"
    if place:
        return place
    if state:
        return state
    return fallback


class NominatimGeocodingProvider:
    def __init__(
        self,
        base_url: str = NOMINATIM_BASE_URL,
        client: httpx.Client | None = None,
        reverse_url: str = NOMINATIM_REVERSE_URL,
    ):
        self._base_url = base_url
        self._reverse_url = reverse_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def reverse(self, latitude: float, longitude: float) -> GeocodeResultData | None:
        """Name a coordinate. Returns None when Nominatim has no match —
        mid-ocean coordinates legitimately have no place name, and that is
        not an error."""
        try:
            response = self._client.get(
                self._reverse_url,
                params={
                    "lat": latitude,
                    "lon": longitude,
                    "format": "jsonv2",
                    "addressdetails": 1,
                    # Roughly city/district level: house-number precision
                    # would put a street address in the Home hero.
                    "zoom": 10,
                },
                headers={
                    "User-Agent": _USER_AGENT,
                    "Accept-Language": _ACCEPT_LANGUAGE,
                },
            )
            response.raise_for_status()
            result = response.json()
            if not result or "error" in result:
                return None

            try:
                address = result.get("address", {})
                return GeocodeResultData(
                    # The coordinate stands in for the query, so the cache
                    # key and the response agree on what was asked.
                    query=f"{latitude},{longitude}",
                    display_name=_short_place_name(
                        address, result.get("display_name", "Current location")
                    ),
                    # The CALLER's coordinates, not Nominatim's snapped
                    # centroid: weather must be fetched for where the user
                    # actually is, not the middle of their district.
                    latitude=latitude,
                    longitude=longitude,
                    country=address.get("country"),
                    state=address.get("state"),
                    raw_payload=result,
                )
            except (KeyError, ValueError, TypeError) as exc:
                logger.warning(
                    "Failed to parse Nominatim reverse result for (%s, %s): %s",
                    latitude,
                    longitude,
                    exc,
                )
                raise
        finally:
            if self._owns_client:
                self._client.close()

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
                headers={
                    "User-Agent": _USER_AGENT,
                    "Accept-Language": _ACCEPT_LANGUAGE,
                },
            )
            response.raise_for_status()
            results = response.json()
            if not results:
                return None

            result = results[0]
            try:
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
            except (KeyError, ValueError, TypeError) as exc:
                logger.warning(
                    "Failed to parse Nominatim result for %r: %s", query, exc
                )
                raise
        finally:
            if self._owns_client:
                self._client.close()
