"""Background scheduler for periodic ingestion jobs.

This is what turns app/ingestion/alerts.py and app/ingestion/marine.py's
"scheduled-ingestion" pattern from a manual-trigger-only endpoint into an
actually-scheduled job, running each at the cadence the spec's cadence
table (section 3) specifies. Deliberately dependency-free (stdlib
threading, no new library) — a fixed-interval background loop per job is
all this needs, matching this codebase's consistent preference for the
simplest tool that fits (no PostGIS, no vendor SDKs elsewhere either).

Each job's exceptions are caught and logged per cycle, never propagated —
a single failed ingestion run must not kill its thread or crash the app;
it simply retries on the next interval.
"""

import logging
import threading
from collections.abc import Callable

logger = logging.getLogger(__name__)


class IngestionScheduler:
    def __init__(self) -> None:
        self._threads: list[threading.Thread] = []
        self._stop_event = threading.Event()

    def _run_job(self, name: str, job_fn: Callable[[], int], interval_seconds: float) -> None:
        while not self._stop_event.is_set():
            try:
                count = job_fn()
                logger.info("Scheduled ingestion '%s' completed: %d rows", name, count)
            except Exception:
                logger.exception("Scheduled ingestion '%s' failed", name)
            self._stop_event.wait(interval_seconds)

    def start(self, jobs: list[tuple[str, Callable[[], int], float]]) -> None:
        for name, job_fn, interval_seconds in jobs:
            thread = threading.Thread(
                target=self._run_job,
                args=(name, job_fn, interval_seconds),
                daemon=True,
                name=f"scheduler-{name}",
            )
            thread.start()
            self._threads.append(thread)

    def stop(self) -> None:
        self._stop_event.set()
        for thread in self._threads:
            thread.join(timeout=5.0)
            if thread.is_alive():
                logger.warning("Scheduler thread %s did not stop within the join timeout", thread.name)
        self._threads = []
