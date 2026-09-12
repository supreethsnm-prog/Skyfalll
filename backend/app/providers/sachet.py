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
        self._client = client or httpx.Client(
            timeout=15.0,
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/120.0.0.0 Safari/537.36 WeatherGPT/1.0"
                )
            },
        )

    def fetch_alerts(self) -> list[AlertData]:
        alerts: list[AlertData] = []
        try:
            try:
                alerts.extend(self._fetch_sdma_alerts())
            except Exception as exc:
                logger.warning("Failed to fetch SDMA alerts: %s", exc)

            try:
                alerts.extend(self._fetch_imd_nowcast_alerts())
            except Exception as exc:
                logger.warning("Failed to fetch IMD nowcast alerts: %s", exc)

            return alerts
        finally:
            if self._owns_client:
                self._client.close()

    def _fetch_sdma_alerts(self) -> list[AlertData]:
        response = self._client.get(f"{self._base_url}/FetchAllAlertDetails")
        response.raise_for_status()
        if not response.text.strip():
            return []
        try:
            records = response.json()
        except Exception as exc:
            logger.warning("Failed to parse SDMA alerts JSON: %s", exc)
            return []
        if not isinstance(records, list):
            return []
        alerts = []
        for record in records:
            try:
                alerts.append(normalize_sdma_alert(record))
            except (KeyError, ValueError, TypeError) as exc:
                logger.warning("Skipping malformed SDMA alert record: %s", exc)
        return alerts

    def _fetch_imd_nowcast_alerts(self) -> list[AlertData]:
        response = self._client.get(f"{self._base_url}/FetchIMDNowcastAlerts")
        response.raise_for_status()
        if not response.text.strip():
            return []
        try:
            data = response.json()
        except Exception as exc:
            logger.warning("Failed to parse IMD nowcast alerts JSON: %s", exc)
            return []
        records = data.get("nowcastDetails", []) if isinstance(data, dict) else []
        alerts = []
        for record in records:
            try:
                alerts.append(normalize_imd_nowcast_alert(record))
            except (KeyError, ValueError, TypeError) as exc:
                logger.warning("Skipping malformed IMD nowcast alert record: %s", exc)
        return alerts
