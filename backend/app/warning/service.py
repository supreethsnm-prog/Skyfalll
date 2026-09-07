"""Query-path read of ingested alert rows — see app/ingestion/alerts.py for
how this table is populated (scheduled-ingestion pattern)."""

import logging

from sqlalchemy import select

from app.db import get_engine
from app.geo import haversine_km
from app.models import Alert

logger = logging.getLogger(__name__)


def list_alerts(
    latitude: float | None = None,
    longitude: float | None = None,
    radius_km: float = 100.0,
) -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    results = [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]

    if latitude is None or longitude is None:
        if latitude is not None or longitude is not None:
            logger.warning(
                "list_alerts received only one of latitude/longitude "
                "(lat=%r, lon=%r) — location filtering requires both, "
                "returning unfiltered results",
                latitude,
                longitude,
            )
        return results

    nearby = []
    for row in results:
        if row["latitude"] is None or row["longitude"] is None:
            # Relevance can't be assessed without coordinates — excluded
            # from a location-filtered result rather than assumed relevant.
            continue
        distance = haversine_km(latitude, longitude, row["latitude"], row["longitude"])
        if distance <= radius_km:
            nearby.append({**row, "distance_km": round(distance, 1)})

    nearby.sort(key=lambda row: row["distance_km"])
    return nearby
