"""Scheduled ingestion for SACHET's bounded, broadcast alert feed (see app/ingestion/marine.py for a second instance of this same pattern) — see app/weather/service.py for the point-location cache-with-TTL pattern and app/geocoding/service.py for the permanent-cache pattern, both used where there's no fixed location set to precompute."""

import logging
from datetime import datetime, timezone

from sqlalchemy import delete, text
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import Alert
from app.providers.warning import WarningProvider

logger = logging.getLogger(__name__)

_IMMUTABLE_COLUMNS = {"id", "external_id"}
_UPSERT_COLUMNS = tuple(
    col.name for col in Alert.__table__.columns if col.name not in _IMMUTABLE_COLUMNS
)

# Arbitrary but stable integer — must stay unique across every
# pg_advisory_xact_lock() key used anywhere in this app, so concurrent
# calls to THIS function serialize with each other without accidentally
# colliding with a different job's lock.
_INGEST_ALERTS_LOCK_KEY = 727001


def ingest_alerts(provider: WarningProvider) -> int:
    alerts = provider.fetch_alerts()
    if not alerts:
        # Deliberately does NOT delete existing rows here — see the plan's
        # "empty fetch" design note. An empty result is indistinguishable
        # from a provider-side bug from inside this function, so we log the
        # anomaly and leave existing data untouched rather than risk turning
        # a transient glitch into total data loss.
        logger.warning("SACHET fetch_alerts() returned zero alerts — leaving existing rows untouched")
        return 0

    fetched_external_ids = {alert.external_id for alert in alerts}
    fetched_sources = {alert.source for alert in alerts}
    fetched_at = datetime.now(timezone.utc)
    with get_engine().begin() as conn:
        conn.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": _INGEST_ALERTS_LOCK_KEY})

        for alert in alerts:
            stmt = pg_insert(Alert).values(
                external_id=alert.external_id,
                source=alert.source,
                severity=alert.severity,
                event_type=alert.event_type,
                area_description=alert.area_description,
                effective_start_time=alert.effective_start_time,
                effective_end_time=alert.effective_end_time,
                warning_message=alert.warning_message,
                severity_color=alert.severity_color,
                latitude=alert.latitude,
                longitude=alert.longitude,
                raw_payload=alert.raw_payload,
                fetched_at=fetched_at,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[Alert.external_id],
                set_={col: getattr(stmt.excluded, col) for col in _UPSERT_COLUMNS},
            )
            conn.execute(stmt)

        # Reconciliation: the feed is authoritative for what's currently
        # active — a row whose external_id wasn't in this fetch has been
        # resolved/expired upstream and is no longer active.
        #
        # Scoped by source, not just by external_id: SACHET's provider
        # concatenates two independent endpoints (SDMA, IMD-NOWCAST) into
        # one list, and each has pre-existing leniency that can silently
        # degrade to zero rows for just ONE of them without the overall
        # fetch being empty. Reconciling only within the sources that
        # actually contributed rows this cycle means a degraded endpoint's
        # existing rows are left untouched (same protective posture as the
        # whole-fetch empty-guard above, applied per source).
        conn.execute(
            delete(Alert).where(
                Alert.source.in_(fetched_sources),
                Alert.external_id.notin_(fetched_external_ids),
            )
        )

    return len(alerts)
