"""One-time seed script for ERA5 historical weather data — NOT part of the
FastAPI app, NOT registered with IngestionScheduler, NOT run by the
automated test suite. Run manually, once (or occasionally, to extend
coverage), by a human, from backend/: `python scripts/seed_era5_history.py`.

A real CDS request takes 25 seconds to 2 minutes (confirmed live — see
docs/superpowers/plans/2026-09-08-era5-historical-provider.md's "Verified
facts"). This script's default matrix (6 cities x 6 dates = 36 requests)
takes roughly 20-40 minutes end to end. This is expected and fine — this
script is meant to be run once, not integrated into any fast path.
"""

import logging
import sys
from datetime import datetime, timezone
from pathlib import Path

# When run directly (`python scripts/seed_era5_history.py`), Python puts this
# file's own directory (backend/scripts) on sys.path[0], NOT the current
# working directory — so `app.*` isn't importable without this. Mirrors the
# same fix in alembic/env.py, which has the identical problem for the same
# reason (a script living one directory below backend/).
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import HistoricalWeatherReading
from app.providers.historical import HistoricalWeatherProvider

logger = logging.getLogger(__name__)

LOCATIONS = [
    ("Mumbai", 19.08, 72.88),
    ("Delhi", 28.61, 77.21),
    ("Chennai", 13.08, 80.27),
    ("Bangalore", 12.97, 77.59),
    ("Kolkata", 22.57, 88.36),
    ("Hyderabad", 17.39, 78.49),
]

DATES = [
    "2023-01-15",  # winter
    "2023-04-15",  # pre-monsoon
    "2023-07-15",  # monsoon
    "2023-10-15",  # post-monsoon
    "2024-01-15",  # winter, second year
    "2024-07-15",  # monsoon, second year
]

DEFAULT_MATRIX = [
    (name, lat, lon, date) for (name, lat, lon) in LOCATIONS for date in DATES
]

_MUTABLE_COLUMNS = (
    "latitude", "longitude", "temp_2m_c", "dewpoint_2m_c", "precip_mm",
    "wind_speed_10m_kmh", "wind_direction_10m_deg", "mslp_hpa", "fetched_at",
)


def seed_era5_history(
    provider: HistoricalWeatherProvider, matrix: list[tuple[str, float, float, str]] | None = None
) -> dict:
    matrix = matrix if matrix is not None else DEFAULT_MATRIX
    succeeded = 0
    failed = 0

    for i, (location_name, latitude, longitude, observation_date) in enumerate(matrix, start=1):
        logger.info(
            "[%d/%d] Fetching %s on %s...", i, len(matrix), location_name, observation_date
        )
        try:
            reading = provider.fetch_reading(location_name, latitude, longitude, observation_date)
        except Exception:
            logger.exception("Failed to fetch %s on %s", location_name, observation_date)
            failed += 1
            continue

        # HistoricalWeatherProvider.fetch_reading is declared to return
        # `Era5ReadingData | None` (see app/providers/historical.py) so that
        # future implementations can report "no data for this
        # (location, date)" without inventing an exception type.
        # CdsEra5Provider (Task 2) never takes this branch today, but this
        # script is written against the Protocol, not just that one
        # implementation — so a None return is handled exactly like a
        # caught exception rather than crashing on reading.location_name.
        if reading is None:
            logger.error(
                "No data returned for %s on %s", location_name, observation_date
            )
            failed += 1
            continue

        fetched_at = datetime.now(timezone.utc)
        with get_engine().begin() as conn:
            stmt = pg_insert(HistoricalWeatherReading).values(
                location_name=reading.location_name,
                latitude=reading.latitude,
                longitude=reading.longitude,
                observation_date=reading.observation_date,
                temp_2m_c=reading.temp_2m_c,
                dewpoint_2m_c=reading.dewpoint_2m_c,
                precip_mm=reading.precip_mm,
                wind_speed_10m_kmh=reading.wind_speed_10m_kmh,
                wind_direction_10m_deg=reading.wind_direction_10m_deg,
                mslp_hpa=reading.mslp_hpa,
                fetched_at=fetched_at,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[
                    HistoricalWeatherReading.location_name,
                    HistoricalWeatherReading.observation_date,
                ],
                set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
            )
            conn.execute(stmt)
        succeeded += 1
        logger.info("[%d/%d] Saved %s on %s", i, len(matrix), location_name, observation_date)

    logger.info("Done: %d succeeded, %d failed out of %d", succeeded, failed, len(matrix))
    return {"succeeded": succeeded, "failed": failed, "total": len(matrix)}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    from app.providers.era5 import CdsEra5Provider

    provider = CdsEra5Provider()
    summary = seed_era5_history(provider)
    sys.exit(0 if summary["failed"] == 0 else 1)
