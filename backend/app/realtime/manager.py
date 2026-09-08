"""In-memory WebSocket connection registry for real-time alert push (spec
section 4's "Real-time dissemination" requirement — the WebSocket half;
FCM for background push is deferred, since it requires a Firebase project
this codebase has no credentials for yet — see this plan's "Explicitly
out of scope" section).

A single process-wide singleton, not per-request state: every connected
client and every ingestion job (scheduled or manually triggered) needs to
share the same registry for the whole app lifetime.
"""

import asyncio
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
        # A client that errors mid-send (already disconnected, network
        # drop) must not stop delivery to every other connected client —
        # collect failures and drop them after the loop, not during it
        # (mutating self._connections while iterating it would be a bug).
        dead: list[WebSocket] = []
        for connection in self._connections:
            try:
                await connection.send_json(message)
            except Exception:
                logger.warning("Dropping a WebSocket connection that failed during broadcast")
                dead.append(connection)
        for connection in dead:
            self._connections.discard(connection)


connection_manager = ConnectionManager()


def make_new_alerts_broadcaster(loop: asyncio.AbstractEventLoop) -> Callable[[list[dict]], object]:
    # Bridges a SYNCHRONOUS caller (app/ingestion/alerts.py's ingest_alerts,
    # which runs on the scheduler's background thread — see
    # app/scheduler.py — or a synchronous request-handling endpoint) into
    # the ASYNC connection_manager.broadcast() coroutine, via the main
    # event loop captured once at app startup (see app/main.py's
    # lifespan). This is the standard asyncio cross-thread bridge — the
    # sync caller never awaits anything, it just schedules the coroutine
    # onto the loop that's already running the WebSocket connections.
    def broadcast_new_alerts(alerts: list[dict]):
        if not alerts:
            return None
        return asyncio.run_coroutine_threadsafe(
            connection_manager.broadcast({"type": "new_alerts", "alerts": alerts}), loop
        )

    return broadcast_new_alerts
