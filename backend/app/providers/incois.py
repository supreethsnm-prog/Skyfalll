import logging

import httpx

from app.providers.marine import PfzZoneData

INCOIS_BASE_URL = "https://incois.gov.in/geoserver/PFZ_Automation/ows"

logger = logging.getLogger(__name__)


def _safe_int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _safe_float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _normalize_feature(feature: dict) -> PfzZoneData:
    properties = feature.get("properties")
    if not isinstance(properties, dict):
        # Covers both an absent "properties" key and a present-but-null
        # (or otherwise non-dict) value — either way there's no usable
        # property data, so treat this feature as malformed like any other.
        raise TypeError(f"properties must be a dict, got {type(properties).__name__!r}")
    return PfzZoneData(
        external_id=feature["id"],
        category=properties.get("Category"),
        sector_boundary=_safe_int(properties.get("SECTORBOUN")),
        sector_name=properties.get("SECTORNAME"),
        julian_day=properties.get("Julian_day"),
        serial_number=properties.get("Sno"),
        year=_safe_int(properties.get("Year")),
        uid=_safe_int(properties.get("UID")),
        length_km=_safe_float(properties.get("Length")),
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
                except (KeyError, TypeError, AttributeError) as exc:
                    logger.warning(
                        "Skipping malformed PFZ feature %r: %s",
                        feature.get("id"),
                        exc,
                    )
            return zones
        finally:
            if self._owns_client:
                self._client.close()
