from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class GeocodeResultData:
    query: str
    display_name: str
    latitude: float
    longitude: float
    country: str | None
    state: str | None
    raw_payload: dict[str, Any]


class GeocodingProvider(Protocol):
    def geocode(self, query: str) -> GeocodeResultData | None: ...
