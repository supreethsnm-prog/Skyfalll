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

        # All network I/O happens BEFORE the transaction opens (the same
        # ordering app/ingestion/alerts.py uses). Each forecast hour's fetch
        # is ~10s of real HTTP + GRIB decoding; doing that inside an open
        # transaction would hold the advisory lock — and an idle-in-
        # transaction connection — for minutes per cycle, long enough to
        # block a colliding `alembic upgrade head` or to trip a managed
        # Postgres/PgBouncer idle_in_transaction_session_timeout.
        rows: list[dict] = []
        for forecast_hour in forecast_hours:
            points = provider.fetch_india_grid(run_date, run_hour, forecast_hour)
            fetched_at = datetime.now(timezone.utc)
            for point in points:
                rows.append(
                    {
                        "run_date": point.run_date,
                        "run_hour": point.run_hour,
                        "forecast_hour": point.forecast_hour,
                        "valid_time": point.valid_time,
                        "grid_latitude": point.grid_latitude,
                        "grid_longitude": point.grid_longitude,
                        "temp_2m_c": point.temp_2m_c,
                        "relative_humidity_2m_pct": point.relative_humidity_2m_pct,
                        "wind_speed_10m_kmh": point.wind_speed_10m_kmh,
                        "wind_direction_10m_deg": point.wind_direction_10m_deg,
                        "wind_gust_kmh": point.wind_gust_kmh,
                        "precip_rate_mmh": point.precip_rate_mmh,
                        "cape_j_per_kg": point.cape_j_per_kg,
                        "cin_j_per_kg": point.cin_j_per_kg,
                        "cloud_cover_pct": point.cloud_cover_pct,
                        "mslp_hpa": point.mslp_hpa,
                        "fetched_at": fetched_at,
                    }
                )

        if not rows:
            # Deliberately does NOT open the transaction (and so never runs
            # the reconciliation delete below) — see the plan's "empty fetch"
            # design note and alerts.py's matching guard. Every forecast hour
            # yielding zero points is indistinguishable from a provider-side
            # bug from inside this function, so we log the anomaly and leave
            # the existing run's rows untouched rather than let reconciliation
            # turn a transient glitch into total data loss. (A network error
            # is a different scenario: it raises, and the transaction — if
            # already open — rolls back.)
            logger.warning(
                "GFS fetch_india_grid() returned zero points for run %s/%s across all %d "
                "forecast hours — leaving existing rows untouched",
                run_date,
                run_hour,
                len(forecast_hours),
            )
            return 0

        # One prepared statement applied to every row (SQLAlchemy Core's
        # executemany), not one execute() per point. Measured against the
        # real table at one forecast hour's scale (15,609 rows): 65.8s ->
        # 1.3s, i.e. a full 6-hour run drops from ~6.5 minutes of open
        # transaction to under 10 seconds. Upsert semantics are unchanged.
        stmt = pg_insert(GfsForecastPoint)
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

        with get_engine().begin() as conn:
            conn.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": _INGEST_GFS_LOCK_KEY})

            conn.execute(stmt, rows)

            # Reconciliation: a freshly-discovered run wholesale-replaces the
            # previous one — any row not belonging to (run_date, run_hour) is
            # now stale and gone from upstream, unlike alerts.py's
            # external_id-scoped reconciliation of an individually-identified
            # feed.
            #
            # Still in the same transaction as the upsert above: a failure
            # anywhere in this block rolls back both, leaving the previous
            # run's rows fully intact rather than half-replaced.
            conn.execute(
                delete(GfsForecastPoint).where(
                    or_(
                        GfsForecastPoint.run_date != run_date,
                        GfsForecastPoint.run_hour != run_hour,
                    )
                )
            )

        return len(rows)
    finally:
        if owns_provider:
            provider.close()
