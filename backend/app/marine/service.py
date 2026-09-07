"""Query-path read of ingested PFZ zone rows — see app/ingestion/marine.py
for how this table is populated (scheduled-ingestion pattern)."""

from typing import Any

from sqlalchemy import select

from app.db import get_engine
from app.geo import haversine_km
from app.models import PfzZone


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
    results = [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]

    if latitude is None or longitude is None:
        return results

    nearby = []
    for row in results:
        zone_lat, zone_lon = _centroid(row["geometry"])
        distance = haversine_km(latitude, longitude, zone_lat, zone_lon)
        if distance <= radius_km:
            nearby.append({**row, "distance_km": round(distance, 1)})

    nearby.sort(key=lambda row: row["distance_km"])
    return nearby
