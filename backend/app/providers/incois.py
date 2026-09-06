import logging

import httpx

from app.providers.marine import PfzZoneData

INCOIS_BASE_URL = "https://incois.gov.in/geoserver/PFZ_Automation/ows"

logger = logging.getLogger(__name__)


def _normalize_feature(feature: dict) -> PfzZoneData:
    properties = feature.get("properties", {})
    return PfzZoneData(
        external_id=feature["id"],
        category=properties.get("Category"),
        sector_boundary=properties.get("SECTORBOUN"),
        sector_name=properties.get("SECTORNAME"),
        julian_day=properties.get("Julian_day"),
        serial_number=properties.get("Sno"),
        year=properties.get("Year"),
        uid=properties.get("UID"),
        length_km=properties.get("Length"),
        geometry=feature["geometry"],
        raw_payload=feature,
    )


class INCOISMarineProvider:
    def __init__(self, base_url: str = INCOIS_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=15.0)

    def fetch_pfz_zones(self) -> list[PfzZoneData]:
        try:
            response = self._client.get(
                self._base_url,
                params={
                    "service": "WFS",
                    "version": "2.0.0",
                    "request": "GetFeature",
                    "typeNames": "PFZ_Automation:pfzlines",
                    "outputFormat": "application/json",
                },
            )
            response.raise_for_status()
            payload = response.json()

            zones = []
            for feature in payload.get("features", []):
                try:
                    zones.append(_normalize_feature(feature))
                except (KeyError, TypeError) as exc:
                    logger.warning(
                        "Skipping malformed PFZ feature %r: %s",
                        feature.get("id"),
                        exc,
                    )
            return zones
        finally:
            if self._owns_client:
                self._client.close()
