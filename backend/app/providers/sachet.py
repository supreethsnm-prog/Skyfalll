import logging

import httpx

from app.providers.warning import AlertData

logger = logging.getLogger(__name__)

SACHET_BASE_URL = "https://sachet.ndma.gov.in/cap_public_website"


def normalize_sdma_alert(record: dict) -> AlertData:
    longitude = latitude = None
    centroid = record.get("centroid")
    if centroid:
        parts = centroid.split(",")
        if len(parts) == 2:
            longitude, latitude = float(parts[0]), float(parts[1])

    return AlertData(
        external_id=str(record["identifier"]),
        source="SACHET-SDMA",
        severity=record.get("severity", ""),
        event_type=record.get("disaster_type", ""),
        area_description=record.get("area_description"),
        effective_start_time=record.get("effective_start_time"),
        effective_end_time=record.get("effective_end_time"),
        warning_message=record.get("warning_message"),
        severity_color=record.get("severity_color"),
        latitude=latitude,
        longitude=longitude,
        raw_payload=record,
    )


def normalize_imd_nowcast_alert(record: dict) -> AlertData:
    longitude = latitude = None
    coordinates = (record.get("location") or {}).get("coordinates")
    if coordinates and len(coordinates) == 2:
        longitude, latitude = float(coordinates[0]), float(coordinates[1])

    return AlertData(
        external_id=str(record["identifier"]),
        source="SACHET-IMD-NOWCAST",
        severity=record.get("severity", ""),
        event_type=record.get("event_category", ""),
        area_description=record.get("area_description"),
        effective_start_time=record.get("effective_start_time"),
        effective_end_time=record.get("effective_end_time"),
        warning_message=record.get("events"),
        severity_color=record.get("severity_color"),
        latitude=latitude,
        longitude=longitude,
        raw_payload=record,
    )


class SACHETWarningProvider:
    def __init__(self, base_url: str = SACHET_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def fetch_alerts(self) -> list[AlertData]:
        try:
            return self._fetch_sdma_alerts() + self._fetch_imd_nowcast_alerts()
        finally:
            if self._owns_client:
                self._client.close()

    def _fetch_sdma_alerts(self) -> list[AlertData]:
        response = self._client.get(f"{self._base_url}/FetchAllAlertDetails")
        response.raise_for_status()
        alerts = []
        for record in response.json():
            try:
                alerts.append(normalize_sdma_alert(record))
            except (KeyError, ValueError, TypeError) as exc:
                logger.warning("Skipping malformed SDMA alert record: %s", exc)
        return alerts

    def _fetch_imd_nowcast_alerts(self) -> list[AlertData]:
        response = self._client.get(f"{self._base_url}/FetchIMDNowcastAlerts")
        response.raise_for_status()
        records = response.json().get("nowcastDetails", [])
        alerts = []
        for record in records:
            try:
                alerts.append(normalize_imd_nowcast_alert(record))
            except (KeyError, ValueError, TypeError) as exc:
                logger.warning("Skipping malformed IMD nowcast alert record: %s", exc)
        return alerts
