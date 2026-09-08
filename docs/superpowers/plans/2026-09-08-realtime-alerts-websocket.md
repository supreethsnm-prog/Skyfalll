# Real-Time Alert WebSocket Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Satisfy the V1 spec's "Real-time dissemination" requirement (§4) — when a new alert lands in Postgres via scheduled ingestion, push it immediately to connected clients over WebSocket, rather than requiring clients to poll `GET /alerts`.

**Architecture:** A process-wide `ConnectionManager` singleton tracks connected WebSocket clients. `app/ingestion/alerts.py`'s `ingest_alerts()` gains an optional `on_new_alerts` callback, invoked with only the genuinely-new alerts (external_ids not previously in the table) after each successful ingestion transaction commits — never on a rolled-back cycle. Because `ingest_alerts()` runs synchronously on the scheduler's background thread (see `app/scheduler.py`) but WebSocket delivery is asyncio-based, a small bridge (`make_new_alerts_broadcaster`, using `asyncio.run_coroutine_threadsafe` against the event loop captured once at app startup) connects the two without making the ingestion layer itself async or introducing a new dependency.

**Tech Stack:** FastAPI's built-in `WebSocket`/`WebSocketDisconnect` (already available via the existing `fastapi` dependency — no new package). Stdlib `asyncio` for the sync-to-async bridge.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md

## Explicitly out of scope

- **FCM (background push)** — the spec's own §4 text pairs WebSocket with "FCM for background", but FCM requires a Firebase project this codebase has no credentials for (an external setup step, like BHASHINI's pipeline ID). WebSocket alone fully satisfies "real-time dissemination... when a new alert lands in Postgres, connected clients are pushed immediately" for any client that's actively connected (a mobile app in the foreground); background push is a follow-up once a Firebase project exists.
- **Marine (PFZ zone) real-time push** — the spec's "when a new alert lands" language is specific to alerts (SACHET), which change on a ~5 minute cadence; PFZ zones update ~daily (see spec §3's cadence table) and don't carry the same latency-sensitivity. Not adding a second WebSocket channel for a source with no real-time use case.
- **Reconnection/backoff logic, message replay for a client that was briefly disconnected, or any persistence of missed messages** — this is a live push channel, not a message queue. A client that reconnects can always fall back to `GET /alerts` for the current full state; V1 does not need at-least-once delivery semantics.

## Global Constraints

- No new dependency — FastAPI's `WebSocket` support and stdlib `asyncio` only.
- `ingest_alerts()`'s new `on_new_alerts` parameter must default to `None` and be fully backward compatible — every existing call site and every existing test must continue to work unmodified unless this plan explicitly says to change it.
- The broadcast callback fires only after the ingestion transaction has committed — never inside the `with get_engine().begin()` block, and never at all if the transaction rolls back.
- No test may depend on real network access or a real running server process — `ConnectionManager` is tested with a hand-built fake WebSocket double; the end-to-end wiring test uses FastAPI's `TestClient.websocket_connect` (a real Starlette WebSocket protocol exercised entirely in-process) plus a `FakeWarningProvider` (already exists in `tests/conftest.py`), never the real `SACHETWarningProvider`.
- Broadcast payloads never include `raw_payload` or the DB-assigned `id` column (see Task 2's rationale) — consistent with `app/warning/service.py`'s `list_alerts()`, which already excludes `raw_payload` from every response.

---

## Task 1: `ConnectionManager` + `GET /ws/alerts` WebSocket route

**Files:**
- Create: `backend/app/realtime/__init__.py`
- Create: `backend/app/realtime/manager.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_realtime_manager.py`

**Interfaces:**
- Produces: `connection_manager` (a module-level `ConnectionManager` singleton), `ConnectionManager.connect(websocket)` / `.disconnect(websocket)` / `.broadcast(message: dict)` (async), and `make_new_alerts_broadcaster(loop: asyncio.AbstractEventLoop) -> Callable[[list[dict]], concurrent.futures.Future | None]` — a factory returning a SYNCHRONOUS callable that Task 2's `on_new_alerts` parameter will be given, and that Task 3 wires into `app/main.py`'s `lifespan`. The returned callable returns the `concurrent.futures.Future` from `asyncio.run_coroutine_threadsafe` (production callers ignore it; tests use it to wait deterministically for delivery — see Task 3) or `None` if called with an empty list (a no-op, nothing scheduled).

- [ ] **Step 1: Write `backend/app/realtime/__init__.py`**

Empty file (matches `backend/app/voice/__init__.py`'s precedent).

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_realtime_manager.py`:

```python
import asyncio

from app.realtime.manager import ConnectionManager, connection_manager, make_new_alerts_broadcaster


class _FakeWebSocket:
    def __init__(self):
        self.sent: list[dict] = []
        self.accepted = False
        self.raise_on_send = False

    async def accept(self):
        self.accepted = True

    async def send_json(self, message):
        if self.raise_on_send:
            raise RuntimeError("connection closed")
        self.sent.append(message)


def test_connect_accepts_and_registers_the_connection():
    manager = ConnectionManager()
    ws = _FakeWebSocket()
    asyncio.run(manager.connect(ws))
    assert ws.accepted is True
    assert ws in manager._connections


def test_disconnect_removes_the_connection():
    manager = ConnectionManager()
    ws = _FakeWebSocket()
    asyncio.run(manager.connect(ws))
    manager.disconnect(ws)
    assert ws not in manager._connections


def test_disconnect_of_an_unregistered_connection_does_not_raise():
    manager = ConnectionManager()
    ws = _FakeWebSocket()
    manager.disconnect(ws)  # never connected — must be a no-op, not an error


def test_broadcast_sends_the_message_to_every_connected_client():
    manager = ConnectionManager()
    ws1, ws2 = _FakeWebSocket(), _FakeWebSocket()
    asyncio.run(manager.connect(ws1))
    asyncio.run(manager.connect(ws2))
    asyncio.run(manager.broadcast({"type": "new_alerts", "alerts": []}))
    assert ws1.sent == [{"type": "new_alerts", "alerts": []}]
    assert ws2.sent == [{"type": "new_alerts", "alerts": []}]


def test_broadcast_skips_a_failed_client_without_stopping_delivery_to_others():
    manager = ConnectionManager()
    bad, good = _FakeWebSocket(), _FakeWebSocket()
    bad.raise_on_send = True
    asyncio.run(manager.connect(bad))
    asyncio.run(manager.connect(good))
    asyncio.run(manager.broadcast({"type": "new_alerts", "alerts": []}))
    assert good.sent == [{"type": "new_alerts", "alerts": []}]
    assert bad not in manager._connections


def test_make_new_alerts_broadcaster_noops_on_empty_list():
    async def _run():
        loop = asyncio.get_running_loop()
        broadcaster = make_new_alerts_broadcaster(loop)
        result = broadcaster([])
        assert result is None

    asyncio.run(_run())


def test_make_new_alerts_broadcaster_schedules_a_real_broadcast():
    async def _run():
        loop = asyncio.get_running_loop()
        ws = _FakeWebSocket()
        await connection_manager.connect(ws)
        try:
            broadcaster = make_new_alerts_broadcaster(loop)
            future = broadcaster([{"external_id": "x"}])
            await asyncio.wrap_future(future)
            assert ws.sent == [{"type": "new_alerts", "alerts": [{"external_id": "x"}]}]
        finally:
            connection_manager.disconnect(ws)

    asyncio.run(_run())
```

- [ ] **Step 3: Run tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_realtime_manager.py -v`
Expected: FAIL — `app.realtime.manager` doesn't exist.

- [ ] **Step 4: Implement `backend/app/realtime/manager.py`**

```python
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
```

- [ ] **Step 5: Run tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_realtime_manager.py -v`
Expected: PASS, all tests.

- [ ] **Step 6: Add the WebSocket route to `app/main.py`**

Add to the existing import block:

```python
from fastapi import WebSocket, WebSocketDisconnect
```

(FastAPI's import line already exists for `Depends, FastAPI, File, Form, Header, HTTPException, Query, UploadFile` — add `WebSocket, WebSocketDisconnect` to that same line, alphabetized with the rest.)

```python
from app.realtime.manager import connection_manager
```

(add to the existing `from app...` import block, alphabetized)

Add the route (near `/alerts`):

```python
@app.websocket("/ws/alerts")
async def alerts_websocket(websocket: WebSocket) -> None:
    await connection_manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        connection_manager.disconnect(websocket)
```

This endpoint is deliberately one-way in practice (server → client push) — it awaits `receive_text()` purely to detect disconnection (a WebSocket handler must keep receiving or the connection is torn down), not because the server expects any particular client message. Task 3 wires actual broadcasting into it via the ingestion pipeline, not this task.

- [ ] **Step 7: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS (323 pre-existing + 7 new).

- [ ] **Step 8: Commit**

```bash
git add backend/app/realtime/ backend/app/main.py backend/tests/test_realtime_manager.py
git commit -m "feat: add ConnectionManager and GET /ws/alerts WebSocket route"
```

---

## Task 2: `ingest_alerts` gains an `on_new_alerts` callback

**Files:**
- Modify: `backend/app/ingestion/alerts.py`
- Test: `backend/tests/test_ingest_alerts.py`

**Interfaces:**
- Consumes: nothing new from Task 1 — this task is fully independent of the WebSocket/async machinery, testable with a plain synchronous callback.
- Produces: `ingest_alerts(provider: WarningProvider, on_new_alerts: Callable[[list[dict]], None] | None = None) -> int` — unchanged return value/type; Task 3 passes `on_new_alerts=` at both call sites (the scheduled job and the manual endpoint).

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_ingest_alerts.py` (do not remove existing tests — these are additions):

```python
def test_ingest_calls_on_new_alerts_with_only_genuinely_new_alerts(clean_alerts_table):
    from app.providers.warning import AlertData
    from tests.conftest import FakeWarningProvider

    existing = AlertData(
        external_id="old-1", source="SACHET-SDMA", severity="Minor", event_type="Flood",
        area_description=None, effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=None, longitude=None,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([existing]))  # seed the table on a first cycle, no callback

    new_one = AlertData(
        external_id="new-1", source="SACHET-SDMA", severity="Severe", event_type="Cyclone",
        area_description="Odisha coast", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=20.0, longitude=85.0,
        raw_payload={},
    )
    captured = []
    ingest_alerts(FakeWarningProvider([existing, new_one]), on_new_alerts=captured.append)

    assert len(captured) == 1
    assert [a["external_id"] for a in captured[0]] == ["new-1"]
    assert captured[0][0]["severity"] == "Severe"
    assert captured[0][0]["event_type"] == "Cyclone"
    assert "raw_payload" not in captured[0][0]
    assert "id" not in captured[0][0]


def test_ingest_calls_on_new_alerts_with_empty_list_when_nothing_is_new(clean_alerts_table):
    from app.providers.warning import AlertData
    from tests.conftest import FakeWarningProvider

    existing = AlertData(
        external_id="old-1", source="SACHET-SDMA", severity="Minor", event_type="Flood",
        area_description=None, effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=None, longitude=None,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([existing]))

    captured = []
    ingest_alerts(FakeWarningProvider([existing]), on_new_alerts=captured.append)

    assert captured == [[]]


def test_ingest_without_on_new_alerts_still_works_unchanged(clean_alerts_table):
    from app.providers.warning import AlertData
    from tests.conftest import FakeWarningProvider

    alert = AlertData(
        external_id="a-1", source="SACHET-SDMA", severity="Minor", event_type="Flood",
        area_description=None, effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=None, longitude=None,
        raw_payload={},
    )
    count = ingest_alerts(FakeWarningProvider([alert]))  # no on_new_alerts at all
    assert count == 1


def test_ingest_does_not_call_on_new_alerts_when_fetch_is_empty(clean_alerts_table):
    from tests.conftest import FakeWarningProvider

    captured = []
    count = ingest_alerts(FakeWarningProvider([]), on_new_alerts=captured.append)

    assert count == 0
    assert captured == []  # the empty-fetch guard returns before any callback logic runs
```

Check `tests/conftest.py` and the existing `tests/test_ingest_alerts.py` for the exact real name/location of the fake warning provider double (referenced above as `FakeWarningProvider` — this matches the plan's own prior BHASHINI/advisory-Skills sprints' convention of fakes living in `conftest.py`, but confirm the exact import path before writing the final test file; adjust if it's actually a local helper class inside `test_ingest_alerts.py` itself rather than in `conftest.py`).

- [ ] **Step 2: Run tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_ingest_alerts.py -v`
Expected: FAIL — `ingest_alerts()` doesn't accept `on_new_alerts` yet (`TypeError: unexpected keyword argument`).

- [ ] **Step 3: Implement the change in `backend/app/ingestion/alerts.py`**

Add `select` to the existing `from sqlalchemy import delete, text` line (→ `from sqlalchemy import delete, select, text`) and add `from collections.abc import Callable` to the imports.

Replace the function signature and body:

```python
def ingest_alerts(
    provider: WarningProvider, on_new_alerts: Callable[[list[dict]], None] | None = None
) -> int:
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

        # Captured BEFORE upserting, inside the same lock/transaction, so
        # "new" reflects the table's real state at the instant this cycle
        # started — not a snapshot racing a concurrent ingestion call.
        existing_external_ids = {
            row[0]
            for row in conn.execute(
                select(Alert.external_id).where(Alert.external_id.in_(fetched_external_ids))
            )
        }

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

    # Broadcast only AFTER the transaction has committed (the `with` block
    # above has exited successfully) — a rolled-back ingestion must never
    # notify clients about alerts that were never actually persisted.
    if on_new_alerts is not None:
        new_external_ids = fetched_external_ids - existing_external_ids
        new_alerts = [
            {
                "external_id": alert.external_id,
                "source": alert.source,
                "severity": alert.severity,
                "event_type": alert.event_type,
                "area_description": alert.area_description,
                "effective_start_time": alert.effective_start_time,
                "effective_end_time": alert.effective_end_time,
                "warning_message": alert.warning_message,
                "severity_color": alert.severity_color,
                "latitude": alert.latitude,
                "longitude": alert.longitude,
                "fetched_at": fetched_at.isoformat(),
            }
            for alert in alerts
            if alert.external_id in new_external_ids
        ]
        on_new_alerts(new_alerts)

    return len(alerts)
```

Note: the broadcast payload deliberately omits the DB-assigned `id` column (only known after the row is inserted, and re-querying for it would cost an extra round trip for no real client benefit — `external_id` is already the stable, meaningful identifier a client would correlate against `GET /alerts`'s full listing) and `raw_payload` (excluded everywhere else in this codebase's API surface).

- [ ] **Step 4: Run tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_ingest_alerts.py -v`
Expected: PASS, all tests (existing + new).

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/ingestion/alerts.py backend/tests/test_ingest_alerts.py
git commit -m "feat: add on_new_alerts callback to ingest_alerts for real-time push"
```

---

## Task 3: Wire the scheduler and manual endpoint to broadcast, end-to-end test

**Files:**
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_alerts_websocket.py`

**Interfaces:**
- Consumes: `make_new_alerts_broadcaster` (Task 1), `ingest_alerts(..., on_new_alerts=...)` (Task 2).
- Produces: nothing new for later tasks — this is the sprint's final integration point.

- [ ] **Step 1: Write the failing end-to-end test**

Create `backend/tests/test_alerts_websocket.py`:

```python
from fastapi.testclient import TestClient

from app.ingestion.alerts import ingest_alerts
from app.main import app
from app.providers.warning import AlertData
from tests.conftest import FakeWarningProvider


def _new_alert(**overrides):
    base = dict(
        external_id="ws-test-1", source="SACHET-SDMA", severity="Severe", event_type="Cyclone",
        area_description="Odisha coast", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=20.0, longitude=85.0,
        raw_payload={},
    )
    base.update(overrides)
    return AlertData(**base)


def test_new_alert_ingestion_broadcasts_to_a_connected_websocket_client(clean_alerts_table):
    with TestClient(app) as client:
        with client.websocket_connect("/ws/alerts") as websocket:
            future_holder = {}

            def capture_and_broadcast(alerts):
                future_holder["future"] = app.state.broadcast_new_alerts(alerts)

            ingest_alerts(FakeWarningProvider([_new_alert()]), on_new_alerts=capture_and_broadcast)
            future_holder["future"].result(timeout=5)

            message = websocket.receive_json()

    assert message["type"] == "new_alerts"
    assert [a["external_id"] for a in message["alerts"]] == ["ws-test-1"]
    assert message["alerts"][0]["severity"] == "Severe"


def test_multiple_connected_clients_all_receive_the_same_broadcast(clean_alerts_table):
    with TestClient(app) as client:
        with client.websocket_connect("/ws/alerts") as ws_a:
            with client.websocket_connect("/ws/alerts") as ws_b:
                future_holder = {}

                def capture_and_broadcast(alerts):
                    future_holder["future"] = app.state.broadcast_new_alerts(alerts)

                ingest_alerts(FakeWarningProvider([_new_alert()]), on_new_alerts=capture_and_broadcast)
                future_holder["future"].result(timeout=5)

                message_a = ws_a.receive_json()
                message_b = ws_b.receive_json()

    assert [a["external_id"] for a in message_a["alerts"]] == ["ws-test-1"]
    assert [a["external_id"] for a in message_b["alerts"]] == ["ws-test-1"]


def test_ingestion_with_no_new_alerts_does_not_hang_a_connected_client(clean_alerts_table):
    # Seed the table first so the second ingestion of the SAME alert finds
    # nothing new — proves the "no broadcast" path doesn't somehow still
    # deliver a message (this test would hang on receive_json() if it did,
    # since no message would ever arrive — the timeout on the join below
    # is what actually catches a regression here, not an assertion).
    with TestClient(app) as client:
        ingest_alerts(FakeWarningProvider([_new_alert()]))  # seed, no callback
        with client.websocket_connect("/ws/alerts") as websocket:
            future_holder = {}

            def capture_and_broadcast(alerts):
                future_holder["future"] = app.state.broadcast_new_alerts(alerts)

            ingest_alerts(FakeWarningProvider([_new_alert()]), on_new_alerts=capture_and_broadcast)
            assert future_holder["future"] is None  # nothing new — no coroutine was even scheduled


def test_websocket_disconnect_is_handled_cleanly(clean_alerts_table):
    with TestClient(app) as client:
        with client.websocket_connect("/ws/alerts"):
            pass  # closes on exit of the inner `with` block
    # No assertion beyond "this doesn't raise or hang" — proves
    # connection_manager.disconnect() is reached without error when a
    # client disconnects.
```

- [ ] **Step 2: Run the test, verify it fails**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_alerts_websocket.py -v`
Expected: FAIL — `app.state.broadcast_new_alerts` doesn't exist yet (`AttributeError`).

- [ ] **Step 3: Wire the broadcaster into `app/main.py`**

Add to the existing import block:

```python
from app.realtime.manager import make_new_alerts_broadcaster
```

(combine with Task 1's `from app.realtime.manager import connection_manager` into one line: `from app.realtime.manager import connection_manager, make_new_alerts_broadcaster`)

Add `import asyncio` to the top-level imports if not already present (check first — it likely isn't).

Modify `lifespan`:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # ... existing docstring/comment block about async lifespan unchanged ...
    settings = get_settings()
    scheduler = IngestionScheduler()
    app.state.broadcast_new_alerts = make_new_alerts_broadcaster(asyncio.get_running_loop())
    if settings.enable_scheduler:
        scheduler.start(
            [
                (
                    "alerts",
                    lambda: ingest_alerts(
                        SACHETWarningProvider(), on_new_alerts=app.state.broadcast_new_alerts
                    ),
                    settings.alert_ingestion_interval_seconds,
                ),
                (
                    "marine",
                    lambda: ingest_pfz_zones(INCOISMarineProvider()),
                    settings.marine_ingestion_interval_seconds,
                ),
                (
                    "gfs",
                    lambda: ingest_gfs_forecast(),
                    settings.gfs_ingestion_interval_seconds,
                ),
            ]
        )
    yield
    if settings.enable_scheduler:
        scheduler.stop()
```

(the `marine`/`gfs` job tuples are unchanged — shown here only so the whole list's shape is unambiguous; do not touch them beyond leaving them exactly as they already are)

Modify the manual-trigger endpoint:

```python
@app.post("/internal/ingest/alerts", dependencies=[Depends(verify_internal_api_key)])
def trigger_alert_ingestion() -> dict[str, int]:
    count = ingest_alerts(
        SACHETWarningProvider(), on_new_alerts=getattr(app.state, "broadcast_new_alerts", None)
    )
    return {"ingested": count}
```

The `getattr(..., None)` default (rather than a direct `app.state.broadcast_new_alerts` access) matters specifically because `app.state.broadcast_new_alerts` is only set during `lifespan`'s startup — and this codebase's existing test suite (`tests/test_internal_auth.py`) uses a bare `TestClient(app)` with no `with`-statement, which (confirmed earlier this project) does NOT trigger lifespan events. Those existing tests never reach this function body (they test the auth-rejection path, which raises before the body runs), so this doesn't currently matter in practice — but `getattr` with a default is the defensive, backward-compatible choice regardless, and costs nothing.

- [ ] **Step 4: Run the test, verify it passes**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_alerts_websocket.py -v`
Expected: PASS, all 4 tests.

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS (this task adds 4 new tests on top of Tasks 1+2's additions).

- [ ] **Step 6: Manual live verification (non-blocking, but genuinely runnable — no external credential needed)**

Start the app locally (`uvicorn app.main:app` from `backend/`, or however this project is normally run locally), connect a WebSocket client to `ws://localhost:8000/ws/alerts` (a simple `websocat`/browser devtools/Python `websockets` one-liner is enough), then trigger `POST /internal/ingest/alerts` (with `X-Internal-API-Key` if `INTERNAL_API_KEY` is set) against the REAL SACHET feed, and confirm that if SACHET currently has any alert not already in this machine's `alerts` table, it arrives over the WebSocket within moments. If SACHET's current alerts are already fully ingested (a very likely case, since the scheduler may have already run), this step may see zero messages — that is not a failure, just confirms there was nothing new to report; a full pass requires either a coincidentally-fresh real alert or accepting the offline integration test (Task 3 Step 4) as sufficient proof, since it exercises the identical code path with a fake provider guaranteed to produce a "new" alert.

- [ ] **Step 7: Commit**

```bash
git add backend/app/main.py backend/tests/test_alerts_websocket.py
git commit -m "feat: wire real-time alert broadcast into the scheduler and manual ingest endpoint"
```
