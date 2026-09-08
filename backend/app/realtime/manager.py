"""In-memory WebSocket connection registry for real-time alert push (spec
section 4's "Real-time dissemination" requirement — the WebSocket half;
FCM for background push is deferred, since it requires a Firebase project
this codebase has no credentials for yet — see this plan's "Explicitly
out of scope" section).

A single process-wide singleton, not per-request state: every connected
client and every ingestion job (scheduled or manually triggered) needs to
share the same registry for the whole app lifetime.

Two constraints worth knowing before changing anything here:

1. `connection_manager` is PROCESS-LOCAL. It only ever sees the clients
   connected to its own process, so a multi-worker deployment
   (`uvicorn --workers N`) would silently degrade to a 1-in-N delivery
   lottery: a client connected to worker A would never receive an alert
   ingested by worker B, with no error raised anywhere. Not an issue for
   this project's current single-process deployment, but adding `--workers`
   later requires replacing this in-memory registry with a shared broker
   (Redis pub/sub, Postgres LISTEN/NOTIFY, or similar) first.

2. Broadcast payloads deliberately OMIT the DB-assigned `id` column (see
   app/ingestion/alerts.py, which builds the payload from the provider's
   fetched AlertData, before/without re-reading the assigned ids). Clients
   should correlate a pushed alert with `GET /alerts`'s full listing on
   `external_id`, which is present in both and stable across upserts.
"""

import asyncio
import concurrent.futures
import logging
from collections.abc import Callable

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class ConnectionManager:
    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.add(websocket)

    def disconnect(self, websocket: WebSocket) -> None:
        self._connections.discard(websocket)

    async def broadcast(self, message: dict) -> None:
        # The outer try/except is a backstop against silence, not defensive
        # noise: production schedules this coroutine via
        # asyncio.run_coroutine_threadsafe and discards the returned Future
        # (see make_new_alerts_broadcaster and app/ingestion/alerts.py), so
        # without this, ANY failure here — the one below or a future one —
        # drops a disaster alert with nothing logged anywhere.
        try:
            # Iterate a SNAPSHOT, never the live set. `await
            # connection.send_json(...)` is a genuine suspension point under
            # transport-level backpressure (a slow or stalled client whose
            # write buffer is over its high-water mark), and a DIFFERENT
            # client's connect()/disconnect() — running as its own concurrent
            # task on this same event loop — can mutate self._connections
            # during that suspension. Against a live iterator that raises
            # "RuntimeError: Set changed size during iteration" and aborts the
            # ENTIRE broadcast, so every client not yet reached in the set's
            # arbitrary iteration order never receives the alert.
            #
            # A client that errors mid-send (already disconnected, network
            # drop) must not stop delivery to every other connected client
            # either — collect failures and drop them after the loop, not
            # during it.
            dead: list[WebSocket] = []
            for connection in list(self._connections):
                try:
                    await connection.send_json(message)
                except Exception:
                    logger.warning("Dropping a WebSocket connection that failed during broadcast")
                    dead.append(connection)
            for connection in dead:
                self._connections.discard(connection)
        except Exception:
            logger.exception("Alert broadcast failed")


connection_manager = ConnectionManager()


def make_new_alerts_broadcaster(
    loop: asyncio.AbstractEventLoop,
) -> Callable[[list[dict]], concurrent.futures.Future | None]:
    # Bridges a SYNCHRONOUS caller (app/ingestion/alerts.py's ingest_alerts,
    # which runs on the scheduler's background thread — see
    # app/scheduler.py — or a synchronous request-handling endpoint) into
    # the ASYNC connection_manager.broadcast() coroutine, via the main
    # event loop captured once at app startup (see app/main.py's
    # lifespan). This is the standard asyncio cross-thread bridge — the
    # sync caller never awaits anything, it just schedules the coroutine
    # onto the loop that's already running the WebSocket connections.
    #
    # The return type is load-bearing, not incidental: callers (and several
    # tests) rely on getting a concurrent.futures.Future back for a non-empty
    # list — so they can .result()/wrap_future() it to await the actual
    # delivery — and None for an empty list, where no coroutine is scheduled
    # at all.
    def broadcast_new_alerts(alerts: list[dict]) -> concurrent.futures.Future | None:
        if not alerts:
            return None
        return asyncio.run_coroutine_threadsafe(
            connection_manager.broadcast({"type": "new_alerts", "alerts": alerts}), loop
        )

    return broadcast_new_alerts
