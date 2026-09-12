"""Query-path read of ingested PFZ zone rows — see app/ingestion/marine.py
for how this table is populated (scheduled-ingestion pattern)."""

import logging
from typing import Any

from sqlalchemy import select

from app.db import get_engine
from app.geo import haversine_km
from app.models import PfzZone

logger = logging.getLogger(__name__)


def _centroid(geometry: dict[str, Any]) -> tuple[float, float]:
    """Average every point across every line of a MultiLineString.

    GeoJSON coordinate order is [longitude, latitude] — do not swap these.
    """
    total_lon = total_lat = count = 0.0
    for line in geometry["coordinates"]:
        for lon, lat in line:
            total_lon += lon
            total_lat += lat
            count += 1
    return total_lat / count, total_lon / count


def list_pfz_zones(
    latitude: float | None = None,
    longitude: float | None = None,
    radius_km: float = 200.0,
) -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    results = [
        {
            **{k: v for k, v in row.items() if k != "raw_payload"},
            "category": row["category"] or "PFZ",
        }
        for row in rows
    ]

    if latitude is None or longitude is None:
        if latitude is not None or longitude is not None:
            logger.warning(
                "list_pfz_zones received only one of latitude/longitude "
                "(lat=%r, lon=%r) — location filtering requires both, "
                "returning unfiltered results",
                latitude,
                longitude,
            )
        return results

    nearby = []
    for row in results:
        try:
            zone_lat, zone_lon = _centroid(row["geometry"])
            distance = haversine_km(latitude, longitude, zone_lat, zone_lon)
        except (TypeError, ValueError, ZeroDivisionError, KeyError) as exc:
            logger.warning(
                "Skipping PFZ zone %r with unparseable geometry: %s",
                row["external_id"],
                exc,
            )
            continue
        if distance <= radius_km:
            nearby.append({**row, "distance_km": round(distance, 1)})

    nearby.sort(key=lambda row: row["distance_km"])
    return nearby
