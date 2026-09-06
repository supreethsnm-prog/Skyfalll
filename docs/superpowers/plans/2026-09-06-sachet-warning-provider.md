# SACHET Warning Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the first real provider abstraction from the spec — a `WarningProvider` backed by SACHET's public alert feeds, ingesting normalized alerts into Postgres on demand and exposing them through a Postgres-only query endpoint.

**Architecture:** Alembic-managed `alerts` table (one canonical schema) behind a `WarningProvider` protocol; `SACHETWarningProvider` fetches two differently-shaped SACHET endpoints and normalizes each through its own adapter function into the canonical shape. An ingestion function upserts normalized alerts into Postgres (dedup by `external_id`); a manual-trigger endpoint calls it (no scheduler yet — that's a later sprint). A separate query endpoint reads only from Postgres, never from the provider — this is the ingestion/query split the spec requires.

**Tech Stack:** FastAPI, SQLAlchemy 2.x + Alembic (new to this repo), Postgres (`JSONB`, `INSERT ... ON CONFLICT`), httpx (already pinned) with `httpx.MockTransport` for tests — no new HTTP mocking library needed.

**Spec:** `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md`

## Global Constraints

- Backend is FastAPI + PostgreSQL only (spec §2) — no other framework or database engine.
- The query path must never call an upstream provider live — it only reads from Postgres (spec §3, the ingestion/query split). Ingestion is the only code path allowed to call `SACHETWarningProvider`.
- SACHET is undocumented/reverse-engineered — isolate it entirely behind `WarningProvider`; nothing outside `app/providers/sachet.py` may reference a SACHET URL or SACHET-specific field name (spec §4, Alerts). Automated tests must not call the real SACHET endpoints — use `httpx.MockTransport` with representative fixture data; real-endpoint verification is a manual, one-off step.
- SACHET's two endpoints have different schemas — do not try to unify their parsing logic into one function; one adapter function per endpoint, both producing the same canonical shape (spec §4).
- Every sprint ends in a state that actually runs and is verified before the next task starts — no task is "done" until its verification step has actually been run and its output checked.
- This machine: `python` is on PATH (not `python3`); `docker` is NOT on PATH — use the full path `/c/Users/ACER/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe` for any docker command. Postgres is already running on `127.0.0.1:5432` (shared across worktrees) — confirm with `"$DOCKER" compose ps` before relying on it, don't assume.

---

## File Structure

```
backend/
├── alembic.ini                              # new
├── alembic/                                 # new (alembic init scaffold)
│   ├── env.py                               # edited to use app.config/app.models
│   ├── script.py.mako
│   └── versions/
│       └── <rev>_create_alerts_table.py     # generated
├── requirements.txt                         # add alembic floor
├── requirements.lock                        # regenerated
├── app/
│   ├── models.py                            # new: Base + Alert model
│   ├── main.py                              # modified: add ingestion + query routes
│   └── providers/
│       ├── __init__.py                      # new, empty
│       ├── warning.py                       # new: AlertData, WarningProvider protocol
│       └── sachet.py                        # new: SACHETWarningProvider + adapters
│   └── ingestion/
│       ├── __init__.py                      # new, empty
│       └── alerts.py                        # new: ingest_alerts()
└── tests/
    ├── conftest.py                          # modified: add clean_alerts_table fixture
    ├── test_alerts_table_schema.py          # new
    ├── test_sachet_provider.py              # new
    ├── test_ingest_alerts.py                # new
    └── test_alerts_endpoint.py              # new
```

---

### Task 1: Alembic setup + the `alerts` table

**Files:**
- Modify: `backend/requirements.txt`
- Create: `backend/requirements.lock` (regenerated)
- Create: `backend/alembic.ini`, `backend/alembic/env.py`, `backend/alembic/script.py.mako`, `backend/alembic/versions/<rev>_create_alerts_table.py`
- Create: `backend/app/models.py`
- Test: `backend/tests/test_alerts_table_schema.py`

**Interfaces:**
- Consumes: `app.config:get_settings() -> Settings` (`.database_url`), `app.db:get_engine()`.
- Produces: `app.models:Base` (SQLAlchemy declarative base — Task 2's model doesn't need it, but any future model does) and `app.models:Alert`, a mapped class for table `alerts` with columns: `id` (int, primary key), `external_id` (str, unique, indexed), `source` (str), `severity` (str), `event_type` (str), `area_description` (str, nullable), `effective_start_time` (str, nullable — raw source-format string, e.g. `"Sat Sep 05 16:05:00 IST 2026"`; not parsed into a real datetime in this sprint, see note below), `effective_end_time` (str, nullable, same format), `warning_message` (str, nullable), `severity_color` (str, nullable), `latitude` (float, nullable), `longitude` (float, nullable), `raw_payload` (JSONB, not null), `fetched_at` (timezone-aware datetime, not null). Task 3 and Task 4 both import `Alert` from `app.models`.

Note on `effective_start_time`/`effective_end_time`: SACHET's timestamps look like `"Sat Sep 05 16:05:00 IST 2026"` — Python's `strptime`/`%Z` does not reliably parse arbitrary timezone abbreviations like `"IST"` across platforms. Rather than ship a fragile parser, this sprint stores the raw string as-is. Parsing these into real `datetime` values is explicitly out of scope here — a later sprint can add it once it's needed for actual time-based queries.

- [ ] **Step 1: Add Alembic to dependencies**

Edit `backend/requirements.txt`, add one line (after the existing `sqlalchemy` line):

```
alembic>=1.13
```

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m pip install -r requirements.txt
```
Expected: alembic and its dependencies (Mako, etc.) install with no errors.

- [ ] **Step 2: Regenerate the lockfile**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m pip freeze > requirements.lock
```
Expected: `requirements.lock` now includes `alembic==...` and `Mako==...` alongside the existing pinned versions.

- [ ] **Step 3: Scaffold Alembic**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic init alembic
```
Expected: creates `backend/alembic.ini` and `backend/alembic/` (with `env.py`, `script.py.mako`, `versions/`).

- [ ] **Step 4: Create the Alert model**

Create `backend/app/models.py`:

```python
from sqlalchemy import Column, DateTime, Float, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import declarative_base

Base = declarative_base()


class Alert(Base):
    __tablename__ = "alerts"

    id = Column(Integer, primary_key=True)
    external_id = Column(String, unique=True, nullable=False, index=True)
    source = Column(String, nullable=False)
    severity = Column(String, nullable=False)
    event_type = Column(String, nullable=False)
    area_description = Column(String, nullable=True)
    effective_start_time = Column(String, nullable=True)
    effective_end_time = Column(String, nullable=True)
    warning_message = Column(String, nullable=True)
    severity_color = Column(String, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
```

- [ ] **Step 5: Point Alembic at the app's settings and models**

Open `backend/alembic/env.py`. It has a line near the top like:
```python
config = context.config
```
Right after that line, add:
```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import get_settings
from app.models import Base

config.set_main_option("sqlalchemy.url", get_settings().database_url)
target_metadata = Base.metadata
```
Then find the existing line `target_metadata = None` (generated by `alembic init`) and delete it — the block above replaces it.

- [ ] **Step 6: Write the schema test (RED)**

Create `backend/tests/test_alerts_table_schema.py`:

```python
from sqlalchemy import inspect

from app.db import get_engine


def test_alerts_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "alerts" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("alerts")}
    assert columns == {
        "id",
        "external_id",
        "source",
        "severity",
        "event_type",
        "area_description",
        "effective_start_time",
        "effective_end_time",
        "warning_message",
        "severity_color",
        "latitude",
        "longitude",
        "raw_payload",
        "fetched_at",
    }
```

- [ ] **Step 7: Run the test and confirm it fails**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_alerts_table_schema.py -v
```
Expected: FAIL — `assert "alerts" in inspector.get_table_names()` fails, since the table doesn't exist yet.

- [ ] **Step 8: Generate and review the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic revision --autogenerate -m "create alerts table"
```
Expected: creates a file under `backend/alembic/versions/`. Open it and confirm the `upgrade()` function creates a table named `alerts` with all 14 columns from Step 4, and that `external_id` has a unique constraint/index. If autogenerate missed the unique constraint, add it manually in the generated file's `upgrade()`:
```python
op.create_unique_constraint("uq_alerts_external_id", "alerts", ["external_id"])
```
(Only add this if the autogenerated migration doesn't already include a unique constraint on `external_id` — check first.)

- [ ] **Step 9: Apply the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic upgrade head
```
Expected: output ends with `Running upgrade  -> <rev>, create alerts table`, no errors.

- [ ] **Step 10: Run the test and confirm it passes**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_alerts_table_schema.py -v
```
Expected: PASS.

- [ ] **Step 11: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (existing 3 + this task's 1 = 4 passed).

- [ ] **Step 12: Commit**

```bash
git add backend/requirements.txt backend/requirements.lock backend/alembic.ini backend/alembic/ backend/app/models.py backend/tests/test_alerts_table_schema.py
git commit -m "feat: add Alembic and the alerts table"
```

---

### Task 2: `WarningProvider` protocol + `SACHETWarningProvider`

**Files:**
- Create: `backend/app/providers/__init__.py` (empty)
- Create: `backend/app/providers/warning.py`
- Create: `backend/app/providers/sachet.py`
- Test: `backend/tests/test_sachet_provider.py`

**Interfaces:**
- Consumes: nothing from Task 1 (this task is pure fetch-and-normalize; it never touches the database).
- Produces: `app.providers.warning:AlertData` (a dataclass with fields `external_id: str`, `source: str`, `severity: str`, `event_type: str`, `area_description: str | None`, `effective_start_time: str | None`, `effective_end_time: str | None`, `warning_message: str | None`, `severity_color: str | None`, `latitude: float | None`, `longitude: float | None`, `raw_payload: dict`). `app.providers.warning:WarningProvider` (a `Protocol` with one method, `fetch_alerts(self) -> list[AlertData]`). `app.providers.sachet:SACHETWarningProvider`, a class implementing that protocol, constructible as `SACHETWarningProvider()` (default: real network) or `SACHETWarningProvider(client=some_httpx_client)` (for tests/dependency injection). Task 3 imports `SACHETWarningProvider` from `app.providers.sachet` and the `WarningProvider`/`AlertData` types from `app.providers.warning`.

- [ ] **Step 1: Create the package marker**

Create `backend/app/providers/__init__.py` (empty file).

- [ ] **Step 2: Create the canonical AlertData shape and the provider protocol**

Create `backend/app/providers/warning.py`:

```python
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class AlertData:
    external_id: str
    source: str
    severity: str
    event_type: str
    area_description: str | None
    effective_start_time: str | None
    effective_end_time: str | None
    warning_message: str | None
    severity_color: str | None
    latitude: float | None
    longitude: float | None
    raw_payload: dict[str, Any]


class WarningProvider(Protocol):
    def fetch_alerts(self) -> list[AlertData]: ...
```

- [ ] **Step 3: Write the failing test**

Create `backend/tests/test_sachet_provider.py`:

```python
import httpx

from app.providers.sachet import SACHETWarningProvider

SDMA_FIXTURE = [
    {
        "severity": "ALERT",
        "identifier": 100200300,
        "effective_start_time": "Sat Sep 05 16:05:00 IST 2026",
        "effective_end_time": "Sat Sep 05 18:05:00 IST 2026",
        "disaster_type": "Lightning",
        "area_description": "Belagavi district",
        "severity_level": "Very Likely",
        "type": "Warning",
        "actual_lang": "en",
        "warning_message": "Lightning likely in Belagavi district.",
        "disseminated": "true",
        "severity_color": "orange",
        "alert_id_sdma_autoinc": 42,
        "centroid": "75.1234,15.5678",
        "alert_source": "Karnataka SDMA",
        "area_covered": "Belagavi",
        "sender_org_id": "KA-SDMA",
    }
]

NOWCAST_FIXTURE = {
    "nowcastDetails": [
        {
            "severity": "Watch",
            "effective_start_time": "Sat Sep 05 16:05:00 IST 2026",
            "effective_end_time": "Sat Sep 05 18:05:00 IST 2026",
            "identifier": "64f1a2b3c4d5e6f7a8b9c0d1",
            "entry_time": "Sat Sep 05 16:00:00 IST 2026",
            "area_description": "Kumily",
            "source": "IMD",
            "event_category": "Thunderstorm",
            "severity_color": "yellow",
            "location": {"type": "Point", "coordinates": [77.1599, 9.6]},
            "state_id": "KL",
            "events": "Thunderstorm with lightning likely over Kumily.",
        }
    ]
}


def _handler(request: httpx.Request) -> httpx.Response:
    if request.url.path.endswith("FetchAllAlertDetails"):
        return httpx.Response(200, json=SDMA_FIXTURE)
    if request.url.path.endswith("FetchIMDNowcastAlerts"):
        return httpx.Response(200, json=NOWCAST_FIXTURE)
    return httpx.Response(404)


def test_fetch_alerts_normalizes_both_endpoints():
    client = httpx.Client(transport=httpx.MockTransport(_handler))
    provider = SACHETWarningProvider(client=client)

    alerts = provider.fetch_alerts()

    assert len(alerts) == 2
    sdma_alert = next(a for a in alerts if a.source == "SACHET-SDMA")
    assert sdma_alert.external_id == "100200300"
    assert sdma_alert.severity == "ALERT"
    assert sdma_alert.event_type == "Lightning"
    assert sdma_alert.area_description == "Belagavi district"
    assert sdma_alert.longitude == 75.1234
    assert sdma_alert.latitude == 15.5678
    assert sdma_alert.warning_message == "Lightning likely in Belagavi district."
    assert sdma_alert.raw_payload == SDMA_FIXTURE[0]

    nowcast_alert = next(a for a in alerts if a.source == "SACHET-IMD-NOWCAST")
    assert nowcast_alert.external_id == "64f1a2b3c4d5e6f7a8b9c0d1"
    assert nowcast_alert.severity == "Watch"
    assert nowcast_alert.event_type == "Thunderstorm"
    assert nowcast_alert.area_description == "Kumily"
    assert nowcast_alert.longitude == 77.1599
    assert nowcast_alert.latitude == 9.6
    assert nowcast_alert.warning_message == "Thunderstorm with lightning likely over Kumily."
    assert nowcast_alert.raw_payload == NOWCAST_FIXTURE["nowcastDetails"][0]
```

- [ ] **Step 4: Run the test and confirm it fails**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_sachet_provider.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.providers.sachet'`.

- [ ] **Step 5: Write the minimal implementation**

Create `backend/app/providers/sachet.py`:

```python
import httpx

from app.providers.warning import AlertData

SACHET_BASE_URL = "https://sachet.ndma.gov.in/cap_public_website"


def normalize_sdma_alert(record: dict) -> AlertData:
    longitude = latitude = None
    centroid = record.get("centroid")
    if centroid:
        parts = centroid.split(",")
        if len(parts) == 2:
            longitude, latitude = float(parts[0]), float(parts[1])

    return AlertData(
        external_id=str(record["identifier"]),
        source="SACHET-SDMA",
        severity=record.get("severity", ""),
        event_type=record.get("disaster_type", ""),
        area_description=record.get("area_description"),
        effective_start_time=record.get("effective_start_time"),
        effective_end_time=record.get("effective_end_time"),
        warning_message=record.get("warning_message"),
        severity_color=record.get("severity_color"),
        latitude=latitude,
        longitude=longitude,
        raw_payload=record,
    )


def normalize_imd_nowcast_alert(record: dict) -> AlertData:
    longitude = latitude = None
    coordinates = (record.get("location") or {}).get("coordinates")
    if coordinates and len(coordinates) == 2:
        longitude, latitude = float(coordinates[0]), float(coordinates[1])

    return AlertData(
        external_id=str(record["identifier"]),
        source="SACHET-IMD-NOWCAST",
        severity=record.get("severity", ""),
        event_type=record.get("event_category", ""),
        area_description=record.get("area_description"),
        effective_start_time=record.get("effective_start_time"),
        effective_end_time=record.get("effective_end_time"),
        warning_message=record.get("events"),
        severity_color=record.get("severity_color"),
        latitude=latitude,
        longitude=longitude,
        raw_payload=record,
    )


class SACHETWarningProvider:
    def __init__(self, base_url: str = SACHET_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._client = client or httpx.Client(timeout=10.0)

    def fetch_alerts(self) -> list[AlertData]:
        return self._fetch_sdma_alerts() + self._fetch_imd_nowcast_alerts()

    def _fetch_sdma_alerts(self) -> list[AlertData]:
        response = self._client.get(f"{self._base_url}/FetchAllAlertDetails")
        response.raise_for_status()
        return [normalize_sdma_alert(record) for record in response.json()]

    def _fetch_imd_nowcast_alerts(self) -> list[AlertData]:
        response = self._client.get(f"{self._base_url}/FetchIMDNowcastAlerts")
        response.raise_for_status()
        records = response.json().get("nowcastDetails", [])
        return [normalize_imd_nowcast_alert(record) for record in records]
```

- [ ] **Step 6: Run the test and confirm it passes**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_sachet_provider.py -v
```
Expected: PASS.

- [ ] **Step 7: Manually verify against the real SACHET endpoints (one-off, not part of the automated suite)**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -c "
from app.providers.sachet import SACHETWarningProvider
alerts = SACHETWarningProvider().fetch_alerts()
print(f'{len(alerts)} alerts fetched')
if alerts:
    print(alerts[0])
"
```
Expected: prints a nonzero count and one real alert's fields (exact count/content will vary — SACHET is live data). If this fails (network error, changed response shape), note it in your report as a concern but do not block the task on it — the mocked test is what's graded; this step is a live sanity check per Global Constraints, and SACHET's real-world availability is outside this task's control.

- [ ] **Step 8: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (4 from before + 1 from this task = 5 passed).

- [ ] **Step 9: Commit**

```bash
git add backend/app/providers/ backend/tests/test_sachet_provider.py
git commit -m "feat: add WarningProvider protocol and SACHETWarningProvider"
```

---

### Task 3: Ingestion function + manual-trigger endpoint

**Files:**
- Create: `backend/app/ingestion/__init__.py` (empty)
- Create: `backend/app/ingestion/alerts.py`
- Modify: `backend/tests/conftest.py` (add `clean_alerts_table` fixture)
- Modify: `backend/app/main.py` (add `POST /internal/ingest/alerts`)
- Test: `backend/tests/test_ingest_alerts.py`

**Interfaces:**
- Consumes: `app.providers.warning:AlertData`, `app.providers.warning:WarningProvider` (Task 2); `app.models:Alert` (Task 1); `app.db:get_engine()`.
- Produces: `app.ingestion.alerts:ingest_alerts(provider: WarningProvider) -> int` — calls `provider.fetch_alerts()`, upserts each into the `alerts` table keyed on `external_id` (insert if new, update if it already exists — never a duplicate row), returns the number of alerts processed. Task 4 does not depend on this function directly (it only reads the table), but reuses the same `clean_alerts_table` fixture this task adds to `conftest.py`.

- [ ] **Step 1: Add the test fixture for cleaning up test data**

Add to `backend/tests/conftest.py` (append; keep the existing `reset_db_caches` fixture untouched):

```python
from sqlalchemy import delete

from app.db import get_engine
from app.models import Alert


@pytest.fixture
def clean_alerts_table():
    yield
    with get_engine().begin() as conn:
        conn.execute(delete(Alert))
```

(`pytest` is already imported at the top of this file from the existing `reset_db_caches` fixture — don't add a second `import pytest` line.)

- [ ] **Step 2: Write the failing test**

Create `backend/tests/test_ingest_alerts.py`:

```python
from sqlalchemy import select

from app.db import get_engine
from app.ingestion.alerts import ingest_alerts
from app.models import Alert
from app.providers.warning import AlertData


class _FakeProvider:
    def __init__(self, alerts: list[AlertData]):
        self._alerts = alerts

    def fetch_alerts(self) -> list[AlertData]:
        return self._alerts


def _sample_alert(severity: str = "ALERT") -> AlertData:
    return AlertData(
        external_id="ingest-test-1",
        source="SACHET-SDMA",
        severity=severity,
        event_type="Flood",
        area_description="Test District",
        effective_start_time="Sat Sep 05 16:05:00 IST 2026",
        effective_end_time="Sat Sep 05 18:05:00 IST 2026",
        warning_message="Test warning message.",
        severity_color="red",
        latitude=15.37,
        longitude=75.12,
        raw_payload={"identifier": "ingest-test-1"},
    )


def test_ingest_alerts_inserts_new_alert(clean_alerts_table):
    count = ingest_alerts(_FakeProvider([_sample_alert()]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(Alert).where(Alert.external_id == "ingest-test-1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].severity == "ALERT"


def test_ingest_alerts_upserts_existing_alert_by_external_id(clean_alerts_table):
    ingest_alerts(_FakeProvider([_sample_alert(severity="ALERT")]))
    count = ingest_alerts(_FakeProvider([_sample_alert(severity="WATCH")]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(Alert).where(Alert.external_id == "ingest-test-1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].severity == "WATCH"
```

- [ ] **Step 3: Run the test and confirm it fails**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_ingest_alerts.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.ingestion'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/ingestion/__init__.py` (empty file).

Create `backend/app/ingestion/alerts.py`:

```python
from datetime import datetime, timezone

from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import Alert
from app.providers.warning import WarningProvider

_UPSERT_COLUMNS = (
    "source",
    "severity",
    "event_type",
    "area_description",
    "effective_start_time",
    "effective_end_time",
    "warning_message",
    "severity_color",
    "latitude",
    "longitude",
    "raw_payload",
    "fetched_at",
)


def ingest_alerts(provider: WarningProvider) -> int:
    alerts = provider.fetch_alerts()
    if not alerts:
        return 0

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
    return len(alerts)
```

- [ ] **Step 5: Run the test and confirm it passes**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_ingest_alerts.py -v
```
Expected: PASS (2 passed).

- [ ] **Step 6: Add the manual-trigger endpoint**

Modify `backend/app/main.py`. Current content is:

```python
from fastapi import FastAPI

from app.db import check_db_connection

app = FastAPI(title="WeatherGPT Backend")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/db")
def health_db() -> dict[str, str]:
    check_db_connection()
    return {"status": "ok", "db": "connected"}
```

Change it to:

```python
from fastapi import FastAPI

from app.db import check_db_connection
from app.ingestion.alerts import ingest_alerts
from app.providers.sachet import SACHETWarningProvider

app = FastAPI(title="WeatherGPT Backend")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/db")
def health_db() -> dict[str, str]:
    check_db_connection()
    return {"status": "ok", "db": "connected"}


@app.post("/internal/ingest/alerts")
def trigger_alert_ingestion() -> dict[str, int]:
    count = ingest_alerts(SACHETWarningProvider())
    return {"ingested": count}
```

- [ ] **Step 7: Manually verify the endpoint against real SACHET + real Postgres**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```
In a second terminal:
```bash
curl -s -X POST -w "\nHTTP_STATUS:%{http_code}\n" http://127.0.0.1:8000/internal/ingest/alerts
```
Expected: `{"ingested": <some number>}` and HTTP 200. Stop the server (Ctrl+C) once confirmed. If SACHET is unreachable at verification time, note it as a concern in your report — same caveat as Task 2 Step 7.

- [ ] **Step 8: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (5 from before + 2 from this task = 7 passed).

- [ ] **Step 9: Commit**

```bash
git add backend/app/ingestion/ backend/app/main.py backend/tests/conftest.py backend/tests/test_ingest_alerts.py
git commit -m "feat: add alert ingestion pipeline and manual-trigger endpoint"
```

---

### Task 4: Query endpoint `GET /alerts`

**Files:**
- Modify: `backend/app/main.py` (add `GET /alerts`)
- Test: `backend/tests/test_alerts_endpoint.py`

**Interfaces:**
- Consumes: `app.models:Alert` (Task 1); `app.db:get_engine()`; `app.ingestion.alerts:ingest_alerts` and the `clean_alerts_table` fixture (Task 3), used only in this task's test to seed data.
- Produces: `GET /alerts` → `200`, a JSON array of alert objects (one key per `Alert` column, `fetched_at` serialized as an ISO 8601 string by FastAPI's default encoder). This route must not import or call anything from `app.providers` — it only reads Postgres.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_alerts_endpoint.py`:

```python
from fastapi.testclient import TestClient

from app.ingestion.alerts import ingest_alerts
from app.main import app
from app.providers.warning import AlertData

client = TestClient(app)


class _FakeProvider:
    def __init__(self, alerts: list[AlertData]):
        self._alerts = alerts

    def fetch_alerts(self) -> list[AlertData]:
        return self._alerts


def test_list_alerts_returns_ingested_rows(clean_alerts_table):
    alert = AlertData(
        external_id="endpoint-test-1",
        source="SACHET-SDMA",
        severity="ALERT",
        event_type="Flood",
        area_description="Test District",
        effective_start_time=None,
        effective_end_time=None,
        warning_message="Test warning.",
        severity_color="red",
        latitude=10.0,
        longitude=20.0,
        raw_payload={"identifier": "endpoint-test-1"},
    )
    ingest_alerts(_FakeProvider([alert]))

    response = client.get("/alerts")

    assert response.status_code == 200
    body = response.json()
    matching = [a for a in body if a["external_id"] == "endpoint-test-1"]
    assert len(matching) == 1
    assert matching[0]["severity"] == "ALERT"
    assert matching[0]["area_description"] == "Test District"
```

- [ ] **Step 2: Run the test and confirm it fails**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_alerts_endpoint.py -v
```
Expected: FAIL — `404` (route doesn't exist yet).

- [ ] **Step 3: Write the minimal implementation**

Modify `backend/app/main.py`. Add these imports alongside the existing ones at the top:

```python
from sqlalchemy import select

from app.db import get_engine
from app.models import Alert
```

Add this route at the end of the file:

```python
@app.get("/alerts")
def list_alerts() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    return [dict(row) for row in rows]
```

- [ ] **Step 4: Run the test and confirm it passes**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_alerts_endpoint.py -v
```
Expected: PASS.

- [ ] **Step 5: Manually verify against the running server**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```
In a second terminal:
```bash
curl -s -X POST http://127.0.0.1:8000/internal/ingest/alerts
curl -s -w "\nHTTP_STATUS:%{http_code}\n" http://127.0.0.1:8000/alerts
```
Expected: the second call returns `200` and a JSON array (length matches whatever the ingest call reported, plus anything already in the table). Stop the server (Ctrl+C) once confirmed.

- [ ] **Step 6: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (7 from before + 1 from this task = 8 passed).

- [ ] **Step 7: Commit**

```bash
git add backend/app/main.py backend/tests/test_alerts_endpoint.py
git commit -m "feat: add GET /alerts query endpoint (Postgres-only, no live provider calls)"
```
