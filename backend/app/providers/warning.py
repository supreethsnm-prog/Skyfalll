from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class AlertData:
    external_id: str
    source: str
    severity: str
    event_type: str
    area_description: str | None
    effective_start_time: str | None
    effective_end_time: str | None
    warning_message: str | None
    severity_color: str | None
    latitude: float | None
    longitude: float | None
    raw_payload: dict[str, Any]


class WarningProvider(Protocol):
    def fetch_alerts(self) -> list[AlertData]: ...
