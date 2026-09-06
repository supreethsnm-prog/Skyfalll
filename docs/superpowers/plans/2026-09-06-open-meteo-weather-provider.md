# Open-Meteo Weather Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WeatherGPT's second provider — current-conditions weather by coordinate, backed by Open-Meteo, with a cache-with-TTL-and-live-fallback query path (not scheduled ingestion — this source is point-queried, not a bounded broadcast feed).

**Architecture:** A `weather_readings` Postgres table, one row per rounded coordinate (unique on `(latitude, longitude)`), upserted in place. `GET /weather?lat=..&lon=..` calls `get_weather()`, which checks the cache first: a row younger than 20 minutes is served straight from Postgres with zero network calls; a missing or stale row triggers exactly one live `OpenMeteoWeatherProvider` call, whose result is cached and returned. This is a deliberate, narrow exception to the "no live call in the request path" rule — granted specifically to point-location, officially-documented, generously-rate-limited sources (see spec §3's amendment); it does not apply to SACHET, which stays scheduled-only.

**Tech Stack:** FastAPI, SQLAlchemy 2.x + Alembic (already set up), Postgres (`JSONB`, `INSERT ... ON CONFLICT` on a composite unique constraint), httpx with `httpx.MockTransport` for tests.

**Spec:** `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md` (including the §3 amendment on point-location caching added alongside this plan)

## Global Constraints

- Backend is FastAPI + PostgreSQL only — no other framework or database engine.
- SACHET's ingestion stays strictly scheduled/precompute-only (unaffected by this plan) — the cache-with-TTL-and-live-fallback pattern here is a documented exception specific to point-location, officially-documented sources like Open-Meteo, not a general relaxation.
- The cache key is the CALLER'S rounded input coordinate, never Open-Meteo's returned (grid-snapped) coordinate — get this wrong and repeat queries for the same input never hit the cache.
- Every response returned to a client must exclude `raw_payload` — this was a real bug caught in the previous sprint's final review; this plan builds it in from the start rather than fixing it after.
- Every task ends in a state that actually runs and is verified before the next task starts — no task is "done" until its verification step has actually been run and its output checked.
- This machine: `python` is on PATH (not `python3`); `docker` is NOT on PATH — use the full path `/c/Users/ACER/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe` for any docker command. Postgres is already running on `127.0.0.1:5432` (shared across worktrees) — confirm with `"$DOCKER" compose ps` or `"$DOCKER" ps`, don't assume.

---

## File Structure

```
backend/
├── alembic/versions/<rev>_create_weather_readings_table.py   # generated
├── app/
│   ├── models.py                       # modified: add WeatherReading
│   ├── main.py                         # modified: add GET /weather
│   ├── providers/
│   │   ├── weather.py                  # new: WeatherReadingData, WeatherProvider protocol
│   │   └── open_meteo.py               # new: OpenMeteoWeatherProvider
│   └── weather/
│       ├── __init__.py                 # new, empty
│       └── service.py                  # new: get_weather()
└── tests/
    ├── conftest.py                     # modified: add clean_weather_readings fixture
    ├── test_weather_readings_table_schema.py   # new
    ├── test_open_meteo_provider.py      # new
    ├── test_weather_service.py          # new
    └── test_weather_endpoint.py         # new
```

---

### Task 1: `weather_readings` table

**Files:**
- Modify: `backend/app/models.py`
- Create: `backend/alembic/versions/<rev>_create_weather_readings_table.py` (generated)
- Test: `backend/tests/test_weather_readings_table_schema.py`

**Interfaces:**
- Consumes: `app.db:get_engine()`; `app.models:Base` (already exists).
- Produces: `app.models:WeatherReading`, a mapped class for table `weather_readings` with columns: `id` (int, PK), `latitude` (float, not null), `longitude` (float, not null), `temperature_c` (float, not null), `humidity_pct` (float, not null), `weather_code` (int, not null — WMO weather code), `wind_speed_kmh` (float, not null), `wind_direction_deg` (float, not null), `observed_at` (string, not null — Open-Meteo's raw `current.time` value, e.g. `"2026-09-06T12:00"`; NOT parsed into a real datetime, same reasoning as the `alerts` table's `effective_start_time` — it's a local-time string with no embedded UTC offset), `timezone` (string, not null, e.g. `"Asia/Kolkata"`), `raw_payload` (JSONB, not null — the full raw Open-Meteo response), `fetched_at` (timezone-aware datetime, not null — OUR OWN cache-population timestamp, used for the freshness check; this is NOT the same field as `observed_at`). A unique constraint spans `(latitude, longitude)` — this is a cache table, one row per rounded coordinate, upserted in place. Task 2 does not depend on this table at all (it's a pure fetch-and-normalize task). Task 3 imports `WeatherReading` from `app.models` and relies on this exact column set and the composite unique constraint.

- [ ] **Step 1: Add the model**

Current `backend/app/models.py`:

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

Change it to (add the `UniqueConstraint` import and the new `WeatherReading` class at the end — the `Alert` class is untouched):

```python
from sqlalchemy import Column, DateTime, Float, Integer, String, UniqueConstraint
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


class WeatherReading(Base):
    __tablename__ = "weather_readings"
    __table_args__ = (
        UniqueConstraint("latitude", "longitude", name="uq_weather_readings_lat_lon"),
    )

    id = Column(Integer, primary_key=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    temperature_c = Column(Float, nullable=False)
    humidity_pct = Column(Float, nullable=False)
    weather_code = Column(Integer, nullable=False)
    wind_speed_kmh = Column(Float, nullable=False)
    wind_direction_deg = Column(Float, nullable=False)
    observed_at = Column(String, nullable=False)
    timezone = Column(String, nullable=False)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
```

- [ ] **Step 2: Write the failing test**

Create `backend/tests/test_weather_readings_table_schema.py`:

```python
from sqlalchemy import inspect

from app.db import get_engine


def test_weather_readings_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "weather_readings" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("weather_readings")}
    assert columns == {
        "id",
        "latitude",
        "longitude",
        "temperature_c",
        "humidity_pct",
        "weather_code",
        "wind_speed_kmh",
        "wind_direction_deg",
        "observed_at",
        "timezone",
        "raw_payload",
        "fetched_at",
    }


def test_weather_readings_has_unique_constraint_on_lat_lon():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("weather_readings")
    matching = [
        c for c in constraints if set(c["column_names"]) == {"latitude", "longitude"}
    ]
    assert len(matching) == 1
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_weather_readings_table_schema.py -v
```
Expected: FAIL — `assert "weather_readings" in inspector.get_table_names()` fails, table doesn't exist yet.

- [ ] **Step 4: Generate and review the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic revision --autogenerate -m "create weather_readings table"
```
Expected: creates a file under `backend/alembic/versions/`. Open it and confirm the `upgrade()` function creates a table named `weather_readings` with all 12 columns from Step 1, and that the composite unique constraint on `(latitude, longitude)` is present (look for `op.create_unique_constraint(...)` with both column names, or a unique index covering both). If autogenerate missed it, add manually in the generated file's `upgrade()`:
```python
op.create_unique_constraint("uq_weather_readings_lat_lon", "weather_readings", ["latitude", "longitude"])
```
(Only add this if the autogenerated migration doesn't already include it — check first. Also confirm the migration does NOT touch the existing `alerts` table at all — if it does, something about the autogenerate diff picked up unrelated drift; stop and report BLOCKED rather than applying it.)

- [ ] **Step 5: Apply the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic upgrade head
```
Expected: output ends with `Running upgrade <alerts-rev> -> <new-rev>, create weather_readings table`, no errors.

- [ ] **Step 6: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_weather_readings_table_schema.py -v
```
Expected: both PASS.

- [ ] **Step 7: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (8 existing + 2 from this task = 10 passed).

- [ ] **Step 8: Commit**

```bash
git add backend/app/models.py backend/alembic/versions/ backend/tests/test_weather_readings_table_schema.py
git commit -m "feat: add weather_readings table"
```

---

### Task 2: `WeatherProvider` protocol + `OpenMeteoWeatherProvider`

**Files:**
- Create: `backend/app/providers/weather.py`
- Create: `backend/app/providers/open_meteo.py`
- Test: `backend/tests/test_open_meteo_provider.py`

**Interfaces:**
- Consumes: nothing from Task 1 (this task never touches the database).
- Produces: `app.providers.weather:WeatherReadingData` (a dataclass with fields `latitude: float`, `longitude: float`, `temperature_c: float`, `humidity_pct: float`, `weather_code: int`, `wind_speed_kmh: float`, `wind_direction_deg: float`, `observed_at: str`, `timezone: str`, `raw_payload: dict`). `app.providers.weather:WeatherProvider` (a `Protocol` with `fetch_current(self, latitude: float, longitude: float) -> WeatherReadingData`). `app.providers.open_meteo:OpenMeteoWeatherProvider`, constructible as `OpenMeteoWeatherProvider()` (real network, self-closing client) or `OpenMeteoWeatherProvider(client=some_httpx_client)` (injected client for tests — provider never closes an injected client). Task 3 imports `WeatherProvider`/`WeatherReadingData` from `app.providers.weather` and `OpenMeteoWeatherProvider` from `app.providers.open_meteo`.

**Critical detail:** `fetch_current`'s returned `WeatherReadingData.latitude`/`.longitude` MUST be the `latitude`/`longitude` arguments passed into the method — NOT the (possibly different, grid-snapped) `latitude`/`longitude` fields in Open-Meteo's response JSON. Open-Meteo snaps requested coordinates to its own internal grid (confirmed live: requesting `19.076, 72.8777` returns a response with top-level `"latitude": 19.086115, "longitude": 72.85291`). Task 3's cache lookup is keyed on the caller's rounded input coordinate — if this task returns the snapped coordinate instead, repeat queries will never hit the cache.

- [ ] **Step 1: Create the canonical WeatherReadingData shape and the provider protocol**

Create `backend/app/providers/weather.py`:

```python
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class WeatherReadingData:
    latitude: float
    longitude: float
    temperature_c: float
    humidity_pct: float
    weather_code: int
    wind_speed_kmh: float
    wind_direction_deg: float
    observed_at: str
    timezone: str
    raw_payload: dict[str, Any]


class WeatherProvider(Protocol):
    def fetch_current(self, latitude: float, longitude: float) -> WeatherReadingData: ...
```

- [ ] **Step 2: Write the failing test**

Create `backend/tests/test_open_meteo_provider.py`:

```python
import httpx

from app.providers.open_meteo import OpenMeteoWeatherProvider

SAMPLE_RESPONSE = {
    "latitude": 19.086115,
    "longitude": 72.85291,
    "generationtime_ms": 0.125,
    "utc_offset_seconds": 19800,
    "timezone": "Asia/Kolkata",
    "timezone_abbreviation": "GMT+5:30",
    "elevation": 6.0,
    "current_units": {
        "time": "iso8601",
        "interval": "seconds",
        "temperature_2m": "°C",
        "relative_humidity_2m": "%",
        "weather_code": "wmo code",
        "wind_speed_10m": "km/h",
        "wind_direction_10m": "°",
    },
    "current": {
        "time": "2026-09-06T12:00",
        "interval": 900,
        "temperature_2m": 28.1,
        "relative_humidity_2m": 79,
        "weather_code": 51,
        "wind_speed_10m": 9.7,
        "wind_direction_10m": 255,
    },
}


def _handler(request: httpx.Request) -> httpx.Response:
    assert request.url.path == "/v1/forecast"
    return httpx.Response(200, json=SAMPLE_RESPONSE)


def test_fetch_current_normalizes_response_and_preserves_input_coordinates():
    client = httpx.Client(transport=httpx.MockTransport(_handler))
    provider = OpenMeteoWeatherProvider(client=client)

    reading = provider.fetch_current(latitude=19.08, longitude=72.88)

    # Input coordinates are preserved, NOT Open-Meteo's snapped response coordinates.
    assert reading.latitude == 19.08
    assert reading.longitude == 72.88
    assert reading.temperature_c == 28.1
    assert reading.humidity_pct == 79
    assert reading.weather_code == 51
    assert reading.wind_speed_kmh == 9.7
    assert reading.wind_direction_deg == 255
    assert reading.observed_at == "2026-09-06T12:00"
    assert reading.timezone == "Asia/Kolkata"
    assert reading.raw_payload == SAMPLE_RESPONSE
```

- [ ] **Step 3: Run the test and confirm it fails**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_open_meteo_provider.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.providers.open_meteo'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/providers/open_meteo.py`:

```python
import httpx

from app.providers.weather import WeatherReadingData

OPEN_METEO_BASE_URL = "https://api.open-meteo.com/v1/forecast"
_CURRENT_FIELDS = (
    "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m"
)


class OpenMeteoWeatherProvider:
    def __init__(self, base_url: str = OPEN_METEO_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def fetch_current(self, latitude: float, longitude: float) -> WeatherReadingData:
        try:
            response = self._client.get(
                self._base_url,
                params={
                    "latitude": latitude,
                    "longitude": longitude,
                    "current": _CURRENT_FIELDS,
                    "timezone": "Asia/Kolkata",
                },
            )
            response.raise_for_status()
            payload = response.json()
            current = payload["current"]
            return WeatherReadingData(
                latitude=latitude,
                longitude=longitude,
                temperature_c=current["temperature_2m"],
                humidity_pct=current["relative_humidity_2m"],
                weather_code=current["weather_code"],
                wind_speed_kmh=current["wind_speed_10m"],
                wind_direction_deg=current["wind_direction_10m"],
                observed_at=current["time"],
                timezone=payload["timezone"],
                raw_payload=payload,
            )
        finally:
            if self._owns_client:
                self._client.close()
```

- [ ] **Step 5: Run the test and confirm it passes**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_open_meteo_provider.py -v
```
Expected: PASS.

- [ ] **Step 6: Manually verify against the real Open-Meteo endpoint (one-off, not part of the automated suite)**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -c "
from app.providers.open_meteo import OpenMeteoWeatherProvider
reading = OpenMeteoWeatherProvider().fetch_current(19.076, 72.8777)
print(reading)
"
```
Expected: prints a `WeatherReadingData` with `latitude=19.076, longitude=72.8777` (the input, not a snapped value) and real current-conditions numbers. If this fails (network error, changed response shape), note it in your report as a concern but do not block the task on it — the mocked test is what's graded.

- [ ] **Step 7: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (10 from before + 1 from this task = 11 passed).

- [ ] **Step 8: Commit**

```bash
git add backend/app/providers/weather.py backend/app/providers/open_meteo.py backend/tests/test_open_meteo_provider.py
git commit -m "feat: add WeatherProvider protocol and OpenMeteoWeatherProvider"
```

---

### Task 3: `get_weather()` cache-with-TTL service + `GET /weather` endpoint

**Files:**
- Create: `backend/app/weather/__init__.py` (empty)
- Create: `backend/app/weather/service.py`
- Modify: `backend/tests/conftest.py` (add `clean_weather_readings` fixture)
- Modify: `backend/app/main.py` (add `GET /weather`)
- Test: `backend/tests/test_weather_service.py`
- Test: `backend/tests/test_weather_endpoint.py`

**Interfaces:**
- Consumes: `app.providers.weather:WeatherProvider`, `app.providers.weather:WeatherReadingData` (Task 2); `app.providers.open_meteo:OpenMeteoWeatherProvider` (Task 2); `app.models:WeatherReading` (Task 1); `app.db:get_engine()`.
- Produces: `app.weather.service:get_weather(latitude: float, longitude: float, provider: WeatherProvider | None = None) -> dict`. The returned dict has keys `latitude`, `longitude`, `temperature_c`, `humidity_pct`, `weather_code`, `wind_speed_kmh`, `wind_direction_deg`, `observed_at`, `timezone`, `fetched_at` — it never includes `raw_payload`.

- [ ] **Step 1: Add the test fixture for cleaning up test data**

`backend/tests/conftest.py` currently starts with:
```python
import pytest
from sqlalchemy import delete

from app.config import get_settings
from app.db import get_engine
from app.models import Alert
from app.providers.warning import AlertData
```
`pytest`, `delete`, and `get_engine` are already imported — don't duplicate them. Change the `from app.models import Alert` line to `from app.models import Alert, WeatherReading` (add the one new name to the existing import, don't add a second import line).

Then append this fixture to the end of the file (keep existing fixtures untouched):

```python
@pytest.fixture
def clean_weather_readings():
    yield
    with get_engine().begin() as conn:
        conn.execute(delete(WeatherReading))
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_weather_service.py`:

```python
from datetime import datetime, timedelta, timezone

from sqlalchemy import insert, select

from app.db import get_engine
from app.models import WeatherReading
from app.providers.weather import WeatherReadingData
from app.weather.service import get_weather


class _RaisingProvider:
    def fetch_current(self, latitude, longitude):
        raise AssertionError("provider should not be called on a fresh cache hit")


class _FakeWeatherProvider:
    def __init__(self, reading: WeatherReadingData):
        self._reading = reading
        self.calls = 0

    def fetch_current(self, latitude, longitude):
        self.calls += 1
        return self._reading


def _seed_reading(fetched_at, temperature_c=28.1):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=temperature_c,
                humidity_pct=79,
                weather_code=51,
                wind_speed_kmh=9.7,
                wind_direction_deg=255,
                observed_at="2026-09-06T12:00",
                timezone="Asia/Kolkata",
                raw_payload={"seeded": True},
                fetched_at=fetched_at,
            )
        )


def test_get_weather_returns_fresh_cache_without_calling_provider(clean_weather_readings):
    _seed_reading(fetched_at=datetime.now(timezone.utc))

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    assert result["temperature_c"] == 28.1
    assert "raw_payload" not in result


def test_get_weather_fetches_and_caches_on_missing_row(clean_weather_readings):
    reading = WeatherReadingData(
        latitude=19.08,
        longitude=72.88,
        temperature_c=30.0,
        humidity_pct=60.0,
        weather_code=1,
        wind_speed_kmh=5.0,
        wind_direction_deg=100.0,
        observed_at="2026-09-06T13:00",
        timezone="Asia/Kolkata",
        raw_payload={"live": True},
    )
    provider = _FakeWeatherProvider(reading)

    result = get_weather(19.08, 72.88, provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 30.0
    assert "raw_payload" not in result

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherReading).where(
                WeatherReading.latitude == 19.08, WeatherReading.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1


def test_get_weather_refetches_when_cache_is_stale(clean_weather_readings):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    _seed_reading(fetched_at=stale_time, temperature_c=10.0)

    reading = WeatherReadingData(
        latitude=19.08,
        longitude=72.88,
        temperature_c=35.0,
        humidity_pct=40.0,
        weather_code=2,
        wind_speed_kmh=15.0,
        wind_direction_deg=200.0,
        observed_at="2026-09-06T14:00",
        timezone="Asia/Kolkata",
        raw_payload={"fresh": True},
    )
    provider = _FakeWeatherProvider(reading)

    result = get_weather(19.08, 72.88, provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 35.0

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherReading).where(
                WeatherReading.latitude == 19.08, WeatherReading.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].temperature_c == 35.0
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_weather_service.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.weather'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/weather/__init__.py` (empty file).

Create `backend/app/weather/service.py`:

```python
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import WeatherReading
from app.providers.open_meteo import OpenMeteoWeatherProvider
from app.providers.weather import WeatherProvider

_FRESHNESS_WINDOW = timedelta(minutes=20)
_COORDINATE_PRECISION = 2

_RESPONSE_FIELDS = (
    "latitude",
    "longitude",
    "temperature_c",
    "humidity_pct",
    "weather_code",
    "wind_speed_kmh",
    "wind_direction_deg",
    "observed_at",
    "timezone",
    "fetched_at",
)


def get_weather(
    latitude: float, longitude: float, provider: WeatherProvider | None = None
) -> dict:
    rounded_lat = round(latitude, _COORDINATE_PRECISION)
    rounded_lon = round(longitude, _COORDINATE_PRECISION)

    engine = get_engine()
    now = datetime.now(timezone.utc)

    with engine.connect() as conn:
        row = (
            conn.execute(
                select(WeatherReading).where(
                    WeatherReading.latitude == rounded_lat,
                    WeatherReading.longitude == rounded_lon,
                )
            )
            .mappings()
            .first()
        )

    if row is not None and (now - row["fetched_at"]) < _FRESHNESS_WINDOW:
        return {field: row[field] for field in _RESPONSE_FIELDS}

    reading = (provider or OpenMeteoWeatherProvider()).fetch_current(
        rounded_lat, rounded_lon
    )

    with engine.begin() as conn:
        stmt = pg_insert(WeatherReading).values(
            latitude=rounded_lat,
            longitude=rounded_lon,
            temperature_c=reading.temperature_c,
            humidity_pct=reading.humidity_pct,
            weather_code=reading.weather_code,
            wind_speed_kmh=reading.wind_speed_kmh,
            wind_direction_deg=reading.wind_direction_deg,
            observed_at=reading.observed_at,
            timezone=reading.timezone,
            raw_payload=reading.raw_payload,
            fetched_at=now,
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=[WeatherReading.latitude, WeatherReading.longitude],
            set_={
                "temperature_c": stmt.excluded.temperature_c,
                "humidity_pct": stmt.excluded.humidity_pct,
                "weather_code": stmt.excluded.weather_code,
                "wind_speed_kmh": stmt.excluded.wind_speed_kmh,
                "wind_direction_deg": stmt.excluded.wind_direction_deg,
                "observed_at": stmt.excluded.observed_at,
                "timezone": stmt.excluded.timezone,
                "raw_payload": stmt.excluded.raw_payload,
                "fetched_at": stmt.excluded.fetched_at,
            },
        )
        conn.execute(stmt)

    return {
        "latitude": rounded_lat,
        "longitude": rounded_lon,
        "temperature_c": reading.temperature_c,
        "humidity_pct": reading.humidity_pct,
        "weather_code": reading.weather_code,
        "wind_speed_kmh": reading.wind_speed_kmh,
        "wind_direction_deg": reading.wind_direction_deg,
        "observed_at": reading.observed_at,
        "timezone": reading.timezone,
        "fetched_at": now,
    }
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_weather_service.py -v
```
Expected: PASS (3 passed).

- [ ] **Step 6: Add the endpoint**

Modify `backend/app/main.py`. Current content is:

```python
from fastapi import FastAPI
from sqlalchemy import select

from app.db import check_db_connection, get_engine
from app.ingestion.alerts import ingest_alerts
from app.models import Alert
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


@app.get("/alerts")
def list_alerts() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    return [
        {k: v for k, v in row.items() if k != "raw_payload"}
        for row in rows
    ]
```

Change it to (add the `app.weather.service` import and the new route at the end — everything else is untouched):

```python
from fastapi import FastAPI
from sqlalchemy import select

from app.db import check_db_connection, get_engine
from app.ingestion.alerts import ingest_alerts
from app.models import Alert
from app.providers.sachet import SACHETWarningProvider
from app.weather.service import get_weather

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


@app.get("/alerts")
def list_alerts() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    return [
        {k: v for k, v in row.items() if k != "raw_payload"}
        for row in rows
    ]


@app.get("/weather")
def get_weather_endpoint(lat: float, lon: float) -> dict:
    return get_weather(lat, lon)
```

- [ ] **Step 7: Write the endpoint test**

Create `backend/tests/test_weather_endpoint.py`:

```python
from datetime import datetime, timezone

from sqlalchemy import insert
from fastapi.testclient import TestClient

from app.db import get_engine
from app.main import app
from app.models import WeatherReading

client = TestClient(app)


def test_weather_endpoint_returns_cached_reading(clean_weather_readings):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=28.1,
                humidity_pct=79,
                weather_code=51,
                wind_speed_kmh=9.7,
                wind_direction_deg=255,
                observed_at="2026-09-06T12:00",
                timezone="Asia/Kolkata",
                raw_payload={"cached": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get("/weather", params={"lat": 19.08, "lon": 72.88})

    assert response.status_code == 200
    body = response.json()
    assert body["temperature_c"] == 28.1
    assert "raw_payload" not in body
```

This test never calls the real Open-Meteo endpoint — it pre-seeds a fresh cache row, so `get_weather`'s cache-hit path (which never touches the provider) is what serves the request. This is the same reason the `GET /alerts` test never needed to mock SACHET: a read-only query route backed entirely by Postgres doesn't need network mocking to test.

- [ ] **Step 8: Run the test and confirm it passes**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_weather_endpoint.py -v
```
Expected: PASS.

- [ ] **Step 9: Manually verify against the running server (real Open-Meteo call on first hit, cache on second)**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```
In a second terminal:
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}\n" "http://127.0.0.1:8000/weather?lat=19.076&lon=72.8777"
curl -s -w "\nHTTP_STATUS:%{http_code}\n" "http://127.0.0.1:8000/weather?lat=19.076&lon=72.8777"
```
Expected: both calls return `200` with the same weather data and no `raw_payload` key. The first call may take slightly longer (real Open-Meteo round trip); the second should be near-instant (cache hit). Stop the server (Ctrl+C) once confirmed. If Open-Meteo is unreachable at verification time, note it as a concern but don't block the task — same caveat as Task 2's manual check.

- [ ] **Step 10: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (11 from before + 3 + 1 from this task = 15 passed).

- [ ] **Step 11: Commit**

```bash
git add backend/app/weather/ backend/app/main.py backend/tests/conftest.py backend/tests/test_weather_service.py backend/tests/test_weather_endpoint.py
git commit -m "feat: add cache-with-TTL weather service and GET /weather endpoint"
```
