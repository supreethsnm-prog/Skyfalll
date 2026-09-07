# Ingestion Scheduler and Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every data source in this backend currently only refreshes when someone manually hits `/internal/ingest/*` — nothing runs on its own, even though the spec's cadence table (§3) explicitly specifies a refresh interval per source. This plan adds (1) reconciliation to both scheduled-ingestion jobs, so a row is removed once the upstream feed stops returning it (currently, an alert SACHET has resolved and dropped from its feed lingers in our database forever and keeps being served as active), and (2) a background scheduler that actually runs both ingestion jobs on their spec-defined cadence.

**Architecture:** Reconciliation is a mechanical addition to the existing upsert loop in both `app/ingestion/alerts.py` and `app/ingestion/marine.py` — fetch the full authoritative set (already the pattern), upsert what's present, delete what's absent. The scheduler is a small, dependency-free background-thread runner (no new library — this codebase avoids adding dependencies for something this simple), wired into FastAPI's `lifespan` context manager, gated behind a settings flag that defaults to OFF so a real deployment must opt in, and so nothing that constructs the app or its lifespan (this plan's own wiring tests included) can accidentally spawn a background thread hitting real external APIs.

**Tech Stack:** Same as the rest of the backend — stdlib `threading`, no new dependency.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md (§3's cadence table: SACHET alerts ~5 min, INCOIS PFZ ~daily — this plan uses these exact numbers, not invented ones. §2's "scalable architecture supporting real-time data ingestion" requirement is what this closes.)

## Design decision: what reconciliation does on an EMPTY fetch (read before objecting to the "if not X: return 0" early-return staying in place)

A non-empty fetch reconciles normally: upsert every returned row, then delete any existing row whose external_id was NOT in this fetch (the feed is authoritative — if it's gone, it's no longer active).

An EMPTY fetch does NOT delete everything. This is a deliberate safety choice, not an oversight: this codebase's established risk posture (see `app/weather/service.py`'s stale-cache-fallback on a live-fetch failure) is to prefer serving slightly-stale data over risking a bigger failure. A genuinely-empty result (zero alerts nationwide, zero PFZ zones) is indistinguishable from a provider bug that returns an empty list for the wrong reason (a parsing regression, an API contract change, a transient malformed response) — and wiping every row in the table on an empty fetch would turn that class of bug into instant, total data loss instead of a caught/logged anomaly. The existing `if not alerts: return 0` early-return already does the right thing here; this plan keeps it, and adds a log line noting the anomaly so it's visible rather than silent.

## Design decision: reconciliation is a hard delete, not a soft-delete/archive

No requirement anywhere in the spec calls for historical alert/zone tracking. Adding an `is_active` flag (or similar) would mean threading that filter through every query path (`list_alerts`, `list_pfz_zones`, the chat tools, the REST endpoints) for no requirement that currently exists — a hard delete keeps every existing read path correct by construction, with no new filter to forget. If historical tracking becomes a real requirement later, it's a new, deliberate feature, not a retrofit onto this plan.

## Global Constraints

- **Test safety, non-negotiable**: the scheduler must default to OFF (`Settings.enable_scheduler: bool = False`). Verified directly during planning: bare `TestClient(app)` with no `with`-statement (the pattern every existing test file in this codebase uses — e.g. `client = TestClient(app)` at module level in `test_chat_endpoint.py`/`test_marine_endpoint.py`) does NOT trigger FastAPI/Starlette's lifespan startup/shutdown events at all in the installed version (fastapi 0.141.1 / starlette 1.6.0) — confirmed empirically with a real request through a bare-constructed client, where lifespan events never fired. So existing test files are not at risk today regardless of this flag. The flag still matters for two real reasons: (1) Task 4's own new tests call `lifespan(app)` directly to verify its wiring, which DOES invoke it — those tests must monkeypatch `IngestionScheduler.start`/`stop` so no real thread ever spawns even there; (2) defense-in-depth and correct default behavior for any future context that DOES respect lifespan — a proper `with TestClient(app) as client:` block (the more correct idiom Starlette's own docs recommend, which nothing here uses today but a future refactor could), a real `uvicorn` run during casual local development, or any other ASGI-lifespan-aware caller — none of which should start background network calls unless the person running it explicitly opted in. No test in this plan may ever let a real `IngestionScheduler.start()` call run to completion with a real network-hitting job function.
- No new dependency (`threading`/`time`/stdlib only) — matches this codebase's consistent avoidance of heavier tooling (no PostGIS, no vendor SDKs, raw httpx everywhere).
- Reconciliation must not touch rows that ARE still present in the current fetch beyond the existing upsert (no unnecessary re-writes of unchanged columns beyond what `on_conflict_do_update` already does).
- Scheduler job failures must be isolated per-cycle (an exception in one ingestion run logs and retries next cycle — it must never kill the scheduler thread or crash the app).

---

### Task 1: Reconciliation for alert ingestion

**Files:**
- Modify: `backend/app/ingestion/alerts.py`
- Test: `backend/tests/test_ingest_alerts.py` (extend)

**Interfaces:** No signature change to `ingest_alerts(provider: WarningProvider) -> int` — same call sites (the manual `/internal/ingest/alerts` route, and Task 4's scheduler) are unaffected.

Current `backend/app/ingestion/alerts.py` (read to confirm before editing — shown above in full).

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_ingest_alerts.py` (read the existing file first for its exact fixture/import conventions and mirror them):

```python
def test_ingest_alerts_removes_rows_absent_from_the_latest_fetch(clean_alerts_table):
    stale_alert = AlertData(
        external_id="resolved-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Old", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([stale_alert]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1  # sanity check before reconciliation

    still_active = AlertData(
        external_id="active-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="New", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([still_active]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert {r["external_id"] for r in rows} == {"active-1"}


def test_ingest_alerts_keeps_rows_still_present_in_the_latest_fetch(clean_alerts_table):
    alert = AlertData(
        external_id="persistent-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Still here", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([alert]))
    ingest_alerts(FakeWarningProvider([alert]))  # same external_id, second run

    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "persistent-1"


def test_ingest_alerts_does_not_wipe_existing_rows_on_an_empty_fetch(clean_alerts_table):
    alert = AlertData(
        external_id="keep-me-1", source="SACHET-SDMA", severity="Moderate",
        event_type="Flood", area_description="Should survive", effective_start_time=None,
        effective_end_time=None, warning_message=None, severity_color=None,
        latitude=19.05, longitude=72.87, raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([alert]))

    count = ingest_alerts(FakeWarningProvider([]))  # empty fetch

    assert count == 0
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "keep-me-1"
```

Check the existing imports in the test file — `AlertData`, `FakeWarningProvider`, `ingest_alerts`, `get_engine`, `select`, `Alert` are almost certainly already imported (this file already has passing tests using all of these); add only what's missing.

- [ ] **Step 2: Run them, verify the new ones fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_ingest_alerts.py -v`
Expected: the pre-existing tests PASS unchanged; `test_ingest_alerts_removes_rows_absent_from_the_latest_fetch` FAILS (the stale row is never deleted today). The other two should already pass with the current code (they don't exercise the new behavior) — that's fine, they're regression guards for Step 3's change, not new-behavior tests.

- [ ] **Step 3: Add reconciliation to `app/ingestion/alerts.py`**

Replace the function body:

```python
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
    fetched_at = datetime.now(timezone.utc)
    with get_engine().begin() as conn:
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
        conn.execute(delete(Alert).where(Alert.external_id.notin_(fetched_external_ids)))

    return len(alerts)
```

Add `import logging` and `logger = logging.getLogger(__name__)` near the top of the file (after the existing imports, before `_IMMUTABLE_COLUMNS`), and add `delete` to the existing `from sqlalchemy.dialects.postgresql import insert as pg_insert` — actually `delete` is a plain SQLAlchemy construct, not postgresql-dialect-specific, so add a separate `from sqlalchemy import delete` import line.

- [ ] **Step 4: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_ingest_alerts.py -v`
Expected: PASS, all tests (pre-existing + 3 new).

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS (in particular `test_alerts_endpoint.py` and `test_warning_service.py`, since neither test file's own fixtures change).

- [ ] **Step 6: Commit**

```bash
git add backend/app/ingestion/alerts.py backend/tests/test_ingest_alerts.py
git commit -m "feat: reconcile alert table against the latest SACHET fetch (remove resolved alerts)"
```

---

### Task 2: Reconciliation for marine PFZ zone ingestion

**Files:**
- Modify: `backend/app/ingestion/marine.py`
- Test: `backend/tests/test_ingest_marine.py` (extend)

**Interfaces:** No signature change to `ingest_pfz_zones(provider: MarineProvider) -> int`, mirroring Task 1 exactly for a second data source.

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_ingest_marine.py` (mirror Task 1's three tests exactly, adapted to `PfzZoneData`/`PfzZone`/`_FakeMarineProvider` — read the existing file first for its exact fixture conventions):

```python
def test_ingest_pfz_zones_removes_zones_absent_from_the_latest_fetch(clean_pfz_zones):
    stale_zone = PfzZoneData(
        external_id="old-zone-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[72.8, 19.0], [72.9, 19.1]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([stale_zone]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    assert len(rows) == 1

    current_zone = PfzZoneData(
        external_id="current-zone-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[73.0, 19.2], [73.1, 19.3]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([current_zone]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    assert {r["external_id"] for r in rows} == {"current-zone-1"}


def test_ingest_pfz_zones_keeps_zones_still_present_in_the_latest_fetch(clean_pfz_zones):
    zone = PfzZoneData(
        external_id="persistent-zone-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[72.8, 19.0], [72.9, 19.1]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "persistent-zone-1"


def test_ingest_pfz_zones_does_not_wipe_existing_rows_on_an_empty_fetch(clean_pfz_zones):
    zone = PfzZoneData(
        external_id="keep-me-zone-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[72.8, 19.0], [72.9, 19.1]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    count = ingest_pfz_zones(_FakeMarineProvider([]))

    assert count == 0
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    assert len(rows) == 1
    assert rows[0].external_id == "keep-me-zone-1"
```

- [ ] **Step 2: Run them, verify the new one fails**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_ingest_marine.py -v`
Expected: `test_ingest_pfz_zones_removes_zones_absent_from_the_latest_fetch` FAILS; others pass already.

- [ ] **Step 3: Add reconciliation to `app/ingestion/marine.py`**

Mirror Task 1's Step 3 exactly, adapted to this module:

```python
def ingest_pfz_zones(provider: MarineProvider) -> int:
    zones = provider.fetch_pfz_zones()
    if not zones:
        logger.warning("INCOIS fetch_pfz_zones() returned zero zones — leaving existing rows untouched")
        return 0

    fetched_external_ids = {zone.external_id for zone in zones}
    fetched_at = datetime.now(timezone.utc)
    with get_engine().begin() as conn:
        for zone in zones:
            stmt = pg_insert(PfzZone).values(
                external_id=zone.external_id,
                category=zone.category,
                sector_boundary=zone.sector_boundary,
                sector_name=zone.sector_name,
                julian_day=zone.julian_day,
                serial_number=zone.serial_number,
                year=zone.year,
                uid=zone.uid,
                length_km=zone.length_km,
                geometry=zone.geometry,
                raw_payload=zone.raw_payload,
                fetched_at=fetched_at,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[PfzZone.external_id],
                set_={col: getattr(stmt.excluded, col) for col in _UPSERT_COLUMNS},
            )
            conn.execute(stmt)

        conn.execute(delete(PfzZone).where(PfzZone.external_id.notin_(fetched_external_ids)))

    return len(zones)
```

Add the same `import logging`/`logger`/`from sqlalchemy import delete` additions as Task 1.

- [ ] **Step 4: Run the tests, verify they pass, then the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/ingestion/marine.py backend/tests/test_ingest_marine.py
git commit -m "feat: reconcile PFZ zone table against the latest INCOIS fetch"
```

---

### Task 3: Background ingestion scheduler

**Files:**
- Create: `backend/app/scheduler.py`
- Test: `backend/tests/test_scheduler.py`

**Interfaces:**
- Produces: `IngestionScheduler` class with `start(jobs: list[tuple[str, Callable[[], int], float]]) -> None` and `stop() -> None`, consumed by Task 4. Each tuple is `(name, job_fn, interval_seconds)`.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_scheduler.py`:

```python
import threading
import time

from app.scheduler import IngestionScheduler


def test_runs_job_repeatedly_at_the_given_interval():
    call_times = []
    lock = threading.Lock()

    def job():
        with lock:
            call_times.append(time.monotonic())
        return 1

    scheduler = IngestionScheduler()
    scheduler.start([("test-job", job, 0.05)])
    try:
        time.sleep(0.22)  # should allow ~4 calls at a 0.05s interval
    finally:
        scheduler.stop()

    with lock:
        count = len(call_times)
    assert count >= 3  # timing-tolerant lower bound, not an exact count


def test_stop_halts_further_calls():
    call_count = {"n": 0}
    lock = threading.Lock()

    def job():
        with lock:
            call_count["n"] += 1
        return 1

    scheduler = IngestionScheduler()
    scheduler.start([("test-job", job, 0.02)])
    time.sleep(0.05)
    scheduler.stop()
    with lock:
        count_at_stop = call_count["n"]
    time.sleep(0.1)  # give it time to prove it did NOT keep running
    with lock:
        count_after_wait = call_count["n"]

    assert count_after_wait == count_at_stop


def test_a_failing_job_does_not_stop_the_scheduler_or_crash():
    call_count = {"n": 0}
    lock = threading.Lock()

    def flaky_job():
        with lock:
            call_count["n"] += 1
            current = call_count["n"]
        if current == 1:
            raise RuntimeError("simulated transient failure")
        return 1

    scheduler = IngestionScheduler()
    scheduler.start([("flaky-job", flaky_job, 0.03)])
    try:
        time.sleep(0.15)
    finally:
        scheduler.stop()

    with lock:
        count = call_count["n"]
    assert count >= 2  # it kept running after the first call raised


def test_multiple_jobs_run_independently():
    calls = {"a": 0, "b": 0}
    lock = threading.Lock()

    def job_a():
        with lock:
            calls["a"] += 1
        return 1

    def job_b():
        with lock:
            calls["b"] += 1
        return 1

    scheduler = IngestionScheduler()
    scheduler.start([("job-a", job_a, 0.03), ("job-b", job_b, 0.03)])
    try:
        time.sleep(0.15)
    finally:
        scheduler.stop()

    with lock:
        a_count, b_count = calls["a"], calls["b"]
    assert a_count >= 2
    assert b_count >= 2


def test_stop_is_safe_to_call_when_nothing_was_started():
    scheduler = IngestionScheduler()
    scheduler.stop()  # must not raise
```

- [ ] **Step 2: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_scheduler.py -v`
Expected: FAIL — `app.scheduler` does not exist.

- [ ] **Step 3: Write `app/scheduler.py`**

```python
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
        self._threads = []
```

Note: each job runs immediately on start (the `while` loop checks the job before waiting), then waits `interval_seconds` before the next run — this matches the test expectations above (a 0.05s interval over 0.22s of wall time yields ~4-5 calls: one immediate, then 3-4 more).

- [ ] **Step 4: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_scheduler.py -v`
Expected: PASS, all 5 tests. These tests use real (very short) sleeps and real threads — that's an intentional, necessary exception to "tests never sleep," since a scheduler's correctness IS its timing behavior; the intervals are chosen small enough (0.02-0.05s) that the whole file runs in well under a second.

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/scheduler.py backend/tests/test_scheduler.py
git commit -m "feat: add dependency-free background scheduler for periodic ingestion jobs"
```

---

### Task 4: Wire the scheduler into the app, gated behind a settings flag

**Files:**
- Modify: `backend/app/config.py`
- Modify: `backend/app/main.py`
- Modify: `backend/.env.example`
- Test: `backend/tests/test_scheduler_wiring.py`

**Interfaces:**
- Consumes: `IngestionScheduler` (Task 3), `ingest_alerts`/`ingest_pfz_zones` (Tasks 1/2, already imported in `main.py`).
- Adds `Settings.enable_scheduler: bool = False`, `Settings.alert_ingestion_interval_seconds: int = 300`, `Settings.marine_ingestion_interval_seconds: int = 86400` (300s = 5 min, 86400s = 24h, matching the spec's cadence table exactly).

**This is the one task where getting test isolation wrong has a real consequence** (a test run silently starting real background network calls) — read the Global Constraints section again before starting.

- [ ] **Step 1: Add scheduler settings to `app/config.py`**

Add to `Settings`, after the existing `llm_provider` field:

```python
    enable_scheduler: bool = False
    alert_ingestion_interval_seconds: int = 300
    marine_ingestion_interval_seconds: int = 86400
```

Append to `backend/.env.example`:

```
# Background ingestion scheduler — OFF by default. The test suite constructs
# TestClient(app) in many files, which triggers FastAPI's lifespan events;
# leaving this off by default means test runs never spawn real background
# threads hitting real external APIs. Set to true only when actually running
# the server (locally or deployed) and you want alerts/marine data to refresh
# automatically instead of only via the manual /internal/ingest/* endpoints.
ENABLE_SCHEDULER=false
ALERT_INGESTION_INTERVAL_SECONDS=300
MARINE_INGESTION_INTERVAL_SECONDS=86400
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_scheduler_wiring.py`:

```python
"""Tests for main.py's lifespan wiring of IngestionScheduler.

CRITICAL: none of these tests may let a real IngestionScheduler.start() run
to completion with a real network-hitting job function — see the plan's
Global Constraints. Every test here monkeypatches IngestionScheduler.start/
stop themselves (never lets a real thread spawn) or explicitly confirms
start was NOT called at all.

app.main.lifespan is an async context manager (FastAPI/Starlette's
lifespan= parameter requires one — verified directly: a plain
@contextmanager raises "TypeError: '_GeneratorContextManager' object does
not support the asynchronous context manager protocol" the moment
TestClient tries to `async with` it). These tests drive it with a small
`asyncio.run()` wrapper rather than pytest-asyncio, since nothing else in
this synchronous-everywhere codebase needs a pytest-asyncio dependency for
just this one file.
"""

import asyncio
from unittest.mock import MagicMock

from app.config import get_settings
from app.main import lifespan, app


def _run_lifespan_once():
    async def _run():
        async with lifespan(app):
            pass

    asyncio.run(_run())


def test_scheduler_defaults_to_disabled():
    assert get_settings().enable_scheduler is False


def test_lifespan_does_not_start_scheduler_when_disabled(monkeypatch):
    monkeypatch.setenv("ENABLE_SCHEDULER", "false")
    get_settings.cache_clear()
    mock_start = MagicMock()
    monkeypatch.setattr("app.main.IngestionScheduler.start", mock_start)

    _run_lifespan_once()

    mock_start.assert_not_called()
    get_settings.cache_clear()


def test_lifespan_starts_scheduler_when_enabled(monkeypatch):
    monkeypatch.setenv("ENABLE_SCHEDULER", "true")
    get_settings.cache_clear()
    mock_start = MagicMock()
    mock_stop = MagicMock()
    monkeypatch.setattr("app.main.IngestionScheduler.start", mock_start)
    monkeypatch.setattr("app.main.IngestionScheduler.stop", mock_stop)

    _run_lifespan_once()

    mock_start.assert_called_once()
    jobs = mock_start.call_args[0][0]
    job_names = {job[0] for job in jobs}
    assert job_names == {"alerts", "marine"}
    mock_stop.assert_called_once()
    get_settings.cache_clear()


def test_lifespan_uses_configured_intervals(monkeypatch):
    monkeypatch.setenv("ENABLE_SCHEDULER", "true")
    monkeypatch.setenv("ALERT_INGESTION_INTERVAL_SECONDS", "123")
    monkeypatch.setenv("MARINE_INGESTION_INTERVAL_SECONDS", "456")
    get_settings.cache_clear()
    mock_start = MagicMock()
    monkeypatch.setattr("app.main.IngestionScheduler.start", mock_start)
    monkeypatch.setattr("app.main.IngestionScheduler.stop", MagicMock())

    _run_lifespan_once()

    jobs = mock_start.call_args[0][0]
    intervals = {name: interval for name, _fn, interval in jobs}
    assert intervals["alerts"] == 123
    assert intervals["marine"] == 456
    get_settings.cache_clear()
```

**Verified directly during planning** (not assumed): FastAPI/Starlette's `lifespan=` parameter requires an ASYNC context manager — a plain `@contextmanager`-decorated function fails immediately with `TypeError: '_GeneratorContextManager' object does not support the asynchronous context manager protocol` the moment `TestClient` (or a real ASGI server) tries to `async with` it. `@asynccontextmanager` with `async def lifespan(app):` was confirmed working end-to-end (startup/shutdown events fire correctly, verified with a real `TestClient` request in between). Step 4 below uses `@asynccontextmanager` — do not "simplify" this to a plain sync `@contextmanager` even though the function body itself has nothing to `await`; the body's synchronicity doesn't change what protocol Starlette requires of the object.

- [ ] **Step 3: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_scheduler_wiring.py -v`
Expected: FAIL — no `lifespan` function exists in `app.main`, and `app` isn't constructed with one yet.

- [ ] **Step 4: Wire the scheduler into `app/main.py`**

Add these imports near the top, alongside the existing ones:

```python
from contextlib import asynccontextmanager

from app.config import get_settings
from app.scheduler import IngestionScheduler
```

Replace:

```python
app = FastAPI(title="WeatherGPT Backend")
```

with:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Must be an ASYNC context manager — Starlette's lifespan= parameter
    # calls `async with lifespan_context(app)`, and a plain @contextmanager
    # fails immediately (verified directly: "TypeError: '_GeneratorContextManager'
    # object does not support the asynchronous context manager protocol").
    # The body itself has nothing to await — IngestionScheduler.start()/stop()
    # are synchronous, thread-based calls — but that doesn't change which
    # protocol the object itself must implement.
    settings = get_settings()
    scheduler = IngestionScheduler()
    if settings.enable_scheduler:
        scheduler.start(
            [
                (
                    "alerts",
                    lambda: ingest_alerts(SACHETWarningProvider()),
                    settings.alert_ingestion_interval_seconds,
                ),
                (
                    "marine",
                    lambda: ingest_pfz_zones(INCOISMarineProvider()),
                    settings.marine_ingestion_interval_seconds,
                ),
            ]
        )
    yield
    if settings.enable_scheduler:
        scheduler.stop()


app = FastAPI(title="WeatherGPT Backend", lifespan=lifespan)
```

Note the `if settings.enable_scheduler: scheduler.stop()` on shutdown mirrors the startup guard — calling `stop()` unconditionally would be harmless (Task 3's `test_stop_is_safe_to_call_when_nothing_was_started` proves this), but guarding it keeps the intent symmetric and obvious to a reader.

- [ ] **Step 5: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_scheduler_wiring.py -v`
Expected: PASS, all 4 tests, and none should take longer than a fraction of a second (if any test hangs or takes multiple seconds, STOP — that likely means a real scheduler thread started somewhere; do not proceed until this is understood and fixed).

- [ ] **Step 6: Run the FULL suite and confirm no new hangs or slowdowns**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v --durations=10`
Expected: all tests PASS, and the `--durations=10` output shows nothing related to this change taking unusually long. Every other test file in this suite constructs `TestClient(app)` at module level — confirm none of them show any behavior change (they shouldn't, since `enable_scheduler` defaults to `False` and none of those files set `ENABLE_SCHEDULER=true`).

- [ ] **Step 7: Commit**

```bash
git add backend/app/config.py backend/app/main.py backend/.env.example backend/tests/test_scheduler_wiring.py
git commit -m "feat: wire IngestionScheduler into app lifespan, gated behind ENABLE_SCHEDULER"
```

- [ ] **Step 8: Manual live verification (non-blocking, real network calls — run deliberately, not in a loop)**

This is the one place in this plan where actually seeing the scheduler run against real APIs matters. From `backend/`, with `ENABLE_SCHEDULER` NOT set in `.env` (stays default False for normal use), run this one-off manual check instead of flipping the setting on for the whole app:

```bash
.venv/Scripts/python.exe -c "
import time
from app.scheduler import IngestionScheduler
from app.ingestion.alerts import ingest_alerts
from app.providers.sachet import SACHETWarningProvider

scheduler = IngestionScheduler()
scheduler.start([('alerts', lambda: ingest_alerts(SACHETWarningProvider()), 5)])
time.sleep(12)
scheduler.stop()
print('done — check the log output above for at least 2 completed ingestion cycles')
"
```

Expected: at least 2 log lines like `Scheduled ingestion 'alerts' completed: N rows` (one immediate, one after ~5s), confirming the scheduler genuinely re-runs a real ingestion job on its own without any HTTP request triggering it. Note the actual output in your report.
