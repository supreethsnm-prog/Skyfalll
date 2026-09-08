"""GFS ingestion: discovers the latest published model run and writes its
India-cropped grid to Postgres, reconciling away any older run's rows —
see this plan's spec for why reconciliation here is by (run_date, run_hour)
rather than by external_id presence (app/ingestion/alerts.py's pattern):
a new GFS run is a wholesale replacement of the old one, not an incremental
update to individually-identified records.
"""

import logging
from datetime import datetime, timezone

from sqlalchemy import delete, or_, text
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import GfsForecastPoint
from app.providers.gfs import NoaaGfsProvider
from app.providers.nwp import NWPProvider

logger = logging.getLogger(__name__)

# Arbitrary but stable integer — must stay unique across every
# pg_advisory_xact_lock() key used anywhere in this app, so concurrent
# calls to THIS function serialize with each other without accidentally
# colliding with a different job's lock. Continues the existing sequential
# numbering (727001=alerts, 727002=marine).
_INGEST_GFS_LOCK_KEY = 727003

_DEFAULT_FORECAST_HOURS = [0, 24, 48, 72, 96, 120]

_MUTABLE_COLUMNS = (
    "valid_time", "temp_2m_c", "relative_humidity_2m_pct", "wind_speed_10m_kmh",
    "wind_direction_10m_deg", "wind_gust_kmh", "precip_rate_mmh", "cape_j_per_kg",
    "cin_j_per_kg", "cloud_cover_pct", "mslp_hpa", "fetched_at",
)


def ingest_gfs_forecast(
    provider: NWPProvider | None = None, forecast_hours: list[int] | None = None
) -> int:
    # NoaaGfsProvider owns an httpx.Client that must be closed — but only
    # when THIS function constructed it. A provider passed in (real or
    # fake, e.g. in tests) is the caller's to manage, mirroring the
    # Depends-based provider lifecycles elsewhere in this codebase
    # (app/main.py's get_llm_provider/get_stt_provider/get_tts_provider).
    owns_provider = provider is None
    provider = provider or NoaaGfsProvider()
    forecast_hours = forecast_hours if forecast_hours is not None else _DEFAULT_FORECAST_HOURS

    try:
        run_date, run_hour = provider.discover_latest_run()
        written = 0

        with get_engine().begin() as conn:
            conn.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": _INGEST_GFS_LOCK_KEY})

            for forecast_hour in forecast_hours:
                points = provider.fetch_india_grid(run_date, run_hour, forecast_hour)
                fetched_at = datetime.now(timezone.utc)
                for point in points:
                    stmt = pg_insert(GfsForecastPoint).values(
                        run_date=point.run_date,
                        run_hour=point.run_hour,
                        forecast_hour=point.forecast_hour,
                        valid_time=point.valid_time,
                        grid_latitude=point.grid_latitude,
                        grid_longitude=point.grid_longitude,
                        temp_2m_c=point.temp_2m_c,
                        relative_humidity_2m_pct=point.relative_humidity_2m_pct,
                        wind_speed_10m_kmh=point.wind_speed_10m_kmh,
                        wind_direction_10m_deg=point.wind_direction_10m_deg,
                        wind_gust_kmh=point.wind_gust_kmh,
                        precip_rate_mmh=point.precip_rate_mmh,
                        cape_j_per_kg=point.cape_j_per_kg,
                        cin_j_per_kg=point.cin_j_per_kg,
                        cloud_cover_pct=point.cloud_cover_pct,
                        mslp_hpa=point.mslp_hpa,
                        fetched_at=fetched_at,
                    )
                    stmt = stmt.on_conflict_do_update(
                        index_elements=[
                            GfsForecastPoint.run_date,
                            GfsForecastPoint.run_hour,
                            GfsForecastPoint.forecast_hour,
                            GfsForecastPoint.grid_latitude,
                            GfsForecastPoint.grid_longitude,
                        ],
                        set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
                    )
                    conn.execute(stmt)
                    written += 1

            # Reconciliation: a freshly-discovered run wholesale-replaces the
            # previous one — any row not belonging to (run_date, run_hour) is
            # now stale and gone from upstream, unlike alerts.py's
            # external_id-scoped reconciliation of an individually-identified
            # feed.
            conn.execute(
                delete(GfsForecastPoint).where(
                    or_(
                        GfsForecastPoint.run_date != run_date,
                        GfsForecastPoint.run_hour != run_hour,
                    )
                )
            )

        return written
    finally:
        if owns_provider:
            provider.close()
