from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class PfzZoneData:
    external_id: str
    category: str | None
    sector_boundary: int | None
    sector_name: str | None
    julian_day: str | None
    serial_number: str | None
    year: int | None
    uid: int | None
    length_km: float | None
    geometry: dict[str, Any]
    raw_payload: dict[str, Any]


class MarineProvider(Protocol):
    def fetch_pfz_zones(self) -> list[PfzZoneData]: ...
