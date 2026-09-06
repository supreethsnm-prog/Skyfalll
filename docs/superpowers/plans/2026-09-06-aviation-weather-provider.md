# Aviation Weather Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WeatherGPT's fourth provider — real-time METAR (current airport weather observations) by ICAO station code, backed by aviationweather.gov (NOAA), using the same cache-with-TTL-and-live-fallback pattern as `app/weather/service.py`.

**Architecture:** A `metar_readings` Postgres table, one row per ICAO station code, unique on `icao_id`. `GET /metar?icao=..` calls `get_metar()`, which checks Postgres first: a row younger than 25 minutes is served with zero network calls; a missing or stale row triggers exactly one live `AviationWeatherProvider` call. Unlike the geocoding sprint, this source is generously rate-limited (100 requests/minute, no key, confirmed via its published usage guidance) — it fits the SAME pattern as Open-Meteo, not Nominatim's permanent-cache pattern. This plan also builds in from the start a fix the weather sprint only added after its final review: a live-fetch failure on a stale (not missing) row falls back to serving the stale row rather than raising.

**Tech Stack:** FastAPI, SQLAlchemy 2.x + Alembic (already set up), Postgres (`JSONB`, `INSERT ... ON CONFLICT DO UPDATE ... RETURNING`), httpx with `httpx.MockTransport` for tests.

**Spec:** `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md` (§3's first amendment — point-location, official, generously-rate-limited sources — covers this provider directly, same as Open-Meteo)

## Global Constraints

- Backend is FastAPI + PostgreSQL only — no other framework or database engine.
- This is a cache-with-TTL-and-live-fallback source (like Open-Meteo), NOT a permanent cache (like Nominatim) — aviationweather.gov allows 100 requests/minute with no key, which is "generously rate-limited" per spec §3's first amendment. Use a 25-minute freshness window.
- A live-fetch failure on a STALE row (not a missing one) must serve the stale row instead of raising — this is a real spec §3 guarantee ("an upstream outage... does not break a live chat response — the app serves the last good cache") that a previous sprint (Open-Meteo) initially missed and had to add in a fix wave. Build it in from Task 3's first draft, not after review.
- **Critical, verified-live API detail:** an unknown/invalid ICAO code returns HTTP 204 with an EMPTY response body — NOT a 200 with an empty JSON array (that's how Nominatim signals "not found"; this API is different). Detecting "not found" by attempting `response.json()` on a 204 will raise a JSON decode error on an empty body — check the status code (or body emptiness) BEFORE parsing JSON.
- **Verified-live unit detail:** the API's `visib` field is in statute miles, not kilometers or meters, regardless of the station's native reporting convention (confirmed: VABB's raw METAR encodes `3000` meters visibility; the JSON `visib` field for the same observation is `1.86`, which is the mile-equivalent). Name the corresponding column/field `visibility_sm` — do not call it `visibility_km`.
- Every response returned to a client must exclude `raw_payload`, same rule as every other query endpoint in this codebase.
- Every task ends in a state that actually runs and is verified before the next task starts.
- This machine: `python` on PATH (not `python3`); `docker` NOT on PATH — use the full path `/c/Users/ACER/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe` if any docker command is needed. Postgres already running on `127.0.0.1:5432` (shared across worktrees) — confirm with `"$DOCKER" ps`, don't assume.

---

## File Structure

```
backend/
├── alembic/versions/<rev>_create_metar_readings_table.py   # generated
├── app/
│   ├── models.py                       # modified: add MetarReading
│   ├── main.py                         # modified: add GET /metar
│   ├── providers/
│   │   ├── aviation.py                 # new: MetarReadingData, AviationWeatherProvider protocol
│   │   └── aviationweather.py          # new: AviationWeatherGovProvider
│   └── aviation/
│       ├── __init__.py                 # new, empty
│       └── service.py                  # new: get_metar()
└── tests/
    ├── conftest.py                     # modified: add clean_metar_readings fixture
    ├── test_metar_readings_table_schema.py   # new
    ├── test_aviationweather_provider.py       # new
    ├── test_metar_service.py                  # new
    └── test_metar_endpoint.py                 # new
```

---

### Task 1: `metar_readings` table

**Files:**
- Modify: `backend/app/models.py`
- Create: `backend/alembic/versions/<rev>_create_metar_readings_table.py` (generated)
- Test: `backend/tests/test_metar_readings_table_schema.py`

**Interfaces:**
- Consumes: `app.db:get_engine()`; `app.models:Base` (already exists).
- Produces: `app.models:MetarReading`, a mapped class for table `metar_readings` with columns: `id` (int, PK), `icao_id` (string, unique, indexed, not null — the cache key, always uppercase), `raw_metar` (string, not null — the raw encoded METAR text, e.g. `"METAR VABB 060900Z 28012KT 3000 BR SCT018 FEW025TCU BKN090 30/25 Q1011 NOSIG"`), `observed_at` (string, not null — the API's `reportTime` value as-is, not parsed into a real datetime, same reasoning as every other source-format timestamp in this codebase), `temperature_c` (float, nullable), `dewpoint_c` (float, nullable), `wind_dir_deg` (float, nullable — nullable because METAR wind direction can be reported as variable ("VRB") rather than a number), `wind_speed_kt` (float, nullable — KNOTS, aviation's standard unit, not km/h), `visibility_sm` (float, nullable — STATUTE MILES, see Global Constraints), `flight_category` (string, nullable — e.g. `"IFR"`, `"VFR"`, `"MVFR"`, `"LIFR"`), `station_name` (string, nullable), `latitude` (float, nullable), `longitude` (float, nullable), `raw_payload` (JSONB, not null), `fetched_at` (timezone-aware datetime, not null — our own cache-population timestamp, used for the TTL check). Single-column unique constraint on `icao_id`. Task 3 imports `MetarReading` from `app.models` and relies on this exact column set and constraint.

- [ ] **Step 1: Add the model**

Current `backend/app/models.py` ends with the `GeocodeCache` class (last line is `fetched_at = Column(DateTime(timezone=True), nullable=False)` closing that class). Append this new class at the end of the file (the other three classes are untouched):

```python
class MetarReading(Base):
    __tablename__ = "metar_readings"

    id = Column(Integer, primary_key=True)
    icao_id = Column(String, unique=True, nullable=False)
    raw_metar = Column(String, nullable=False)
    observed_at = Column(String, nullable=False)
    temperature_c = Column(Float, nullable=True)
    dewpoint_c = Column(Float, nullable=True)
    wind_dir_deg = Column(Float, nullable=True)
    wind_speed_kt = Column(Float, nullable=True)
    visibility_sm = Column(Float, nullable=True)
    flight_category = Column(String, nullable=True)
    station_name = Column(String, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
```

No new imports are needed — `Column`, `DateTime`, `Float`, `Integer`, `String`, `JSONB` are already imported at the top of the file. Note: `icao_id` uses `unique=True` alone (NOT `unique=True, index=True` together) — that combination was found in an earlier sprint to produce a Postgres unique INDEX rather than a table-level UNIQUE CONSTRAINT, which `get_unique_constraints()` (used in Step 2's test) cannot see. `unique=True` alone is already backed by an implicit index.

- [ ] **Step 2: Write the failing test**

Create `backend/tests/test_metar_readings_table_schema.py`:

```python
from sqlalchemy import inspect

from app.db import get_engine


def test_metar_readings_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "metar_readings" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("metar_readings")}
    assert columns == {
        "id",
        "icao_id",
        "raw_metar",
        "observed_at",
        "temperature_c",
        "dewpoint_c",
        "wind_dir_deg",
        "wind_speed_kt",
        "visibility_sm",
        "flight_category",
        "station_name",
        "latitude",
        "longitude",
        "raw_payload",
        "fetched_at",
    }


def test_metar_readings_has_unique_constraint_on_icao_id():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("metar_readings")
    matching = [c for c in constraints if c["column_names"] == ["icao_id"]]
    assert len(matching) == 1
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_metar_readings_table_schema.py -v
```
Expected: FAIL — table doesn't exist yet.

- [ ] **Step 4: Generate and review the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic revision --autogenerate -m "create metar_readings table"
```
Expected: creates a file under `backend/alembic/versions/`. Open it and confirm `upgrade()` creates a table named `metar_readings` with all 15 columns from Step 1 and a unique constraint on `icao_id` alone. Also confirm `upgrade()`/`downgrade()` do NOT touch `alerts`, `weather_readings`, or `geocode_cache` — if they do, stop and report BLOCKED rather than applying it.

- [ ] **Step 5: Apply the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic upgrade head
```
Expected: output ends with `Running upgrade <geocode_cache-rev> -> <new-rev>, create metar_readings table`, no errors.

- [ ] **Step 6: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_metar_readings_table_schema.py -v
```
Expected: both PASS.

- [ ] **Step 7: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (27 existing + 2 from this task = 29 passed).

- [ ] **Step 8: Commit**

```bash
git add backend/app/models.py backend/alembic/versions/ backend/tests/test_metar_readings_table_schema.py
git commit -m "feat: add metar_readings table"
```

---

### Task 2: `AviationWeatherProvider` protocol + `AviationWeatherGovProvider`

**Files:**
- Create: `backend/app/providers/aviation.py`
- Create: `backend/app/providers/aviationweather.py`
- Test: `backend/tests/test_aviationweather_provider.py`

**Interfaces:**
- Consumes: nothing from Task 1 (this task never touches the database).
- Produces: `app.providers.aviation:MetarReadingData` (a dataclass with fields `icao_id: str`, `raw_metar: str`, `observed_at: str`, `temperature_c: float | None`, `dewpoint_c: float | None`, `wind_dir_deg: float | None`, `wind_speed_kt: float | None`, `visibility_sm: float | None`, `flight_category: str | None`, `station_name: str | None`, `latitude: float | None`, `longitude: float | None`, `raw_payload: dict`). `app.providers.aviation:AviationWeatherProvider` (a `Protocol` with `fetch_metar(self, icao_id: str) -> MetarReadingData | None`, where `None` means "no data for this station" — not an error). `app.providers.aviationweather:AviationWeatherGovProvider`, constructible as `AviationWeatherGovProvider()` (real network, self-closing client) or `AviationWeatherGovProvider(client=some_httpx_client)` (injected for tests). Task 3 imports `AviationWeatherProvider`/`MetarReadingData` from `app.providers.aviation` and `AviationWeatherGovProvider` from `app.providers.aviationweather`.

**Critical detail:** a station code with no data returns HTTP 204 with an EMPTY body — checking `if not response.text:` (or `response.status_code == 204`) BEFORE calling `response.json()` is required; calling `.json()` on an empty body raises a decode error, which is not the same thing as "not found" and must not be confused with it.

- [ ] **Step 1: Create the canonical MetarReadingData shape and the provider protocol**

Create `backend/app/providers/aviation.py`:

```python
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class MetarReadingData:
    icao_id: str
    raw_metar: str
    observed_at: str
    temperature_c: float | None
    dewpoint_c: float | None
    wind_dir_deg: float | None
    wind_speed_kt: float | None
    visibility_sm: float | None
    flight_category: str | None
    station_name: str | None
    latitude: float | None
    longitude: float | None
    raw_payload: dict[str, Any]


class AviationWeatherProvider(Protocol):
    def fetch_metar(self, icao_id: str) -> MetarReadingData | None: ...
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_aviationweather_provider.py`:

```python
import httpx

from app.providers.aviationweather import AviationWeatherGovProvider

FOUND_RESPONSE = [
    {
        "icaoId": "VABB",
        "receiptTime": "2026-09-06T09:06:14.422Z",
        "obsTime": 1788685200,
        "reportTime": "2026-09-06T09:00:00.000Z",
        "temp": 30,
        "dewp": 25,
        "wdir": 280,
        "wspd": 12,
        "visib": 1.86,
        "altim": 1011,
        "qcField": 16,
        "wxString": "BR",
        "metarType": "METAR",
        "rawOb": "METAR VABB 060900Z 28012KT 3000 BR SCT018 FEW025TCU BKN090 30/25 Q1011 NOSIG",
        "lat": 19.1,
        "lon": 72.859,
        "elev": 14,
        "name": "Mumbai/Shivaji Intl, MM, IN",
        "cover": "BKN",
        "clouds": [
            {"cover": "SCT", "base": 1800},
            {"cover": "FEW", "base": 2500},
            {"cover": "BKN", "base": 9000},
        ],
        "fltCat": "IFR",
    }
]


def _found_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=FOUND_RESPONSE)


def _not_found_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(204, content=b"")


def test_fetch_metar_returns_normalized_result_when_found():
    client = httpx.Client(transport=httpx.MockTransport(_found_handler))
    provider = AviationWeatherGovProvider(client=client)

    result = provider.fetch_metar("VABB")

    assert result is not None
    assert result.icao_id == "VABB"
    assert result.raw_metar == (
        "METAR VABB 060900Z 28012KT 3000 BR SCT018 FEW025TCU BKN090 30/25 Q1011 NOSIG"
    )
    assert result.observed_at == "2026-09-06T09:00:00.000Z"
    assert result.temperature_c == 30
    assert result.dewpoint_c == 25
    assert result.wind_dir_deg == 280
    assert result.wind_speed_kt == 12
    assert result.visibility_sm == 1.86
    assert result.flight_category == "IFR"
    assert result.station_name == "Mumbai/Shivaji Intl, MM, IN"
    assert result.latitude == 19.1
    assert result.longitude == 72.859
    assert result.raw_payload == FOUND_RESPONSE[0]


def test_fetch_metar_returns_none_on_204_empty_response():
    client = httpx.Client(transport=httpx.MockTransport(_not_found_handler))
    provider = AviationWeatherGovProvider(client=client)

    result = provider.fetch_metar("ZZZZ")

    assert result is None
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_aviationweather_provider.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.providers.aviationweather'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/providers/aviationweather.py`:

```python
import httpx

from app.providers.aviation import MetarReadingData

AVIATIONWEATHER_BASE_URL = "https://aviationweather.gov/api/data/metar"


def _safe_float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


class AviationWeatherGovProvider:
    def __init__(self, base_url: str = AVIATIONWEATHER_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def fetch_metar(self, icao_id: str) -> MetarReadingData | None:
        try:
            response = self._client.get(
                self._base_url,
                params={"ids": icao_id, "format": "json"},
            )
            if response.status_code == 204 or not response.text:
                return None
            response.raise_for_status()
            results = response.json()
            if not results:
                return None

            result = results[0]
            return MetarReadingData(
                icao_id=result["icaoId"],
                raw_metar=result["rawOb"],
                observed_at=result["reportTime"],
                temperature_c=_safe_float(result.get("temp")),
                dewpoint_c=_safe_float(result.get("dewp")),
                wind_dir_deg=_safe_float(result.get("wdir")),
                wind_speed_kt=_safe_float(result.get("wspd")),
                visibility_sm=_safe_float(result.get("visib")),
                flight_category=result.get("fltCat"),
                station_name=result.get("name"),
                latitude=_safe_float(result.get("lat")),
                longitude=_safe_float(result.get("lon")),
                raw_payload=result,
            )
        finally:
            if self._owns_client:
                self._client.close()
```

`_safe_float` handles fields that could be non-numeric in real-world data (e.g. `wdir` reported as `"VRB"` for variable wind) by returning `None` instead of raising — the same defensive-parsing posture already used for the other providers' schema-variable fields.

- [ ] **Step 5: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_aviationweather_provider.py -v
```
Expected: PASS (2 passed).

- [ ] **Step 6: Manually verify against the real aviationweather.gov endpoint (one-off, not part of the automated suite)**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -c "
from app.providers.aviationweather import AviationWeatherGovProvider
result = AviationWeatherGovProvider().fetch_metar('VIDP')
print(result)
not_found = AviationWeatherGovProvider().fetch_metar('ZZZZ')
print('not found result:', not_found)
"
```
Expected: the first call prints a `MetarReadingData` with real current conditions for Delhi airport; the second prints `not found result: None`. If this fails (network error, changed response shape), note it in your report as a concern but do not block the task on it — the mocked tests are what's graded.

- [ ] **Step 7: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (29 from before + 2 from this task = 31 passed).

- [ ] **Step 8: Commit**

```bash
git add backend/app/providers/aviation.py backend/app/providers/aviationweather.py backend/tests/test_aviationweather_provider.py
git commit -m "feat: add AviationWeatherProvider protocol and AviationWeatherGovProvider"
```

---

### Task 3: `get_metar()` cache-with-TTL service + `GET /metar` endpoint

**Files:**
- Create: `backend/app/aviation/__init__.py` (empty)
- Create: `backend/app/aviation/service.py`
- Modify: `backend/tests/conftest.py` (add `clean_metar_readings` fixture)
- Modify: `backend/app/main.py` (add `GET /metar`)
- Test: `backend/tests/test_metar_service.py`
- Test: `backend/tests/test_metar_endpoint.py`

**Interfaces:**
- Consumes: `app.providers.aviation:AviationWeatherProvider`, `app.providers.aviation:MetarReadingData` (Task 2); `app.providers.aviationweather:AviationWeatherGovProvider` (Task 2); `app.models:MetarReading` (Task 1); `app.db:get_engine()`.
- Produces: `app.aviation.service:get_metar(icao_id: str, provider: AviationWeatherProvider | None = None) -> dict | None`. Returns `None` if the station has no data (nothing is written to the cache in that case — same as a genuinely unknown station). The returned dict has keys `icao_id`, `raw_metar`, `observed_at`, `temperature_c`, `dewpoint_c`, `wind_dir_deg`, `wind_speed_kt`, `visibility_sm`, `flight_category`, `station_name`, `latitude`, `longitude`, `fetched_at` — never `raw_payload`.

- [ ] **Step 1: Add the test fixture for cleaning up test data**

`backend/tests/conftest.py` currently starts with:
```python
import pytest
from sqlalchemy import delete

from app.config import get_settings
from app.db import get_engine
from app.models import Alert, GeocodeCache, WeatherReading
from app.providers.warning import AlertData
```
Change the `from app.models import Alert, GeocodeCache, WeatherReading` line to `from app.models import Alert, GeocodeCache, MetarReading, WeatherReading` (add the one new name, keep alphabetical order, don't add a second import line).

Then append this fixture to the end of the file (keep existing fixtures untouched):

```python
@pytest.fixture
def clean_metar_readings():
    yield
    with get_engine().begin() as conn:
        conn.execute(delete(MetarReading))
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_metar_service.py`:

```python
from datetime import datetime, timedelta, timezone

from sqlalchemy import insert, select

from app.aviation.service import get_metar
from app.db import get_engine
from app.models import MetarReading
from app.providers.aviation import MetarReadingData


class _RaisingProvider:
    def fetch_metar(self, icao_id):
        raise AssertionError("provider should not be called on a fresh cache hit")


class _FakeAviationProvider:
    def __init__(self, reading: MetarReadingData | None, exc: Exception | None = None):
        self._reading = reading
        self._exc = exc
        self.calls = 0

    def fetch_metar(self, icao_id):
        self.calls += 1
        if self._exc is not None:
            raise self._exc
        return self._reading


def _sample_reading(icao_id="VABB", temperature_c=30.0) -> MetarReadingData:
    return MetarReadingData(
        icao_id=icao_id,
        raw_metar="METAR VABB 060900Z 28012KT 3000 BR SCT018 BKN090 30/25 Q1011 NOSIG",
        observed_at="2026-09-06T09:00:00.000Z",
        temperature_c=temperature_c,
        dewpoint_c=25.0,
        wind_dir_deg=280.0,
        wind_speed_kt=12.0,
        visibility_sm=1.86,
        flight_category="IFR",
        station_name="Mumbai/Shivaji Intl, MM, IN",
        latitude=19.1,
        longitude=72.859,
        raw_payload={"icaoId": icao_id},
    )


def _seed_reading(fetched_at, icao_id="VABB", temperature_c=30.0):
    reading = _sample_reading(icao_id, temperature_c)
    with get_engine().begin() as conn:
        conn.execute(
            insert(MetarReading).values(
                icao_id=reading.icao_id,
                raw_metar=reading.raw_metar,
                observed_at=reading.observed_at,
                temperature_c=reading.temperature_c,
                dewpoint_c=reading.dewpoint_c,
                wind_dir_deg=reading.wind_dir_deg,
                wind_speed_kt=reading.wind_speed_kt,
                visibility_sm=reading.visibility_sm,
                flight_category=reading.flight_category,
                station_name=reading.station_name,
                latitude=reading.latitude,
                longitude=reading.longitude,
                raw_payload=reading.raw_payload,
                fetched_at=fetched_at,
            )
        )


def test_get_metar_returns_fresh_cache_without_calling_provider(clean_metar_readings):
    _seed_reading(fetched_at=datetime.now(timezone.utc))

    result = get_metar("VABB", provider=_RaisingProvider())

    assert result["temperature_c"] == 30.0
    assert "raw_payload" not in result


def test_get_metar_fetches_and_caches_on_missing_row(clean_metar_readings):
    provider = _FakeAviationProvider(_sample_reading())

    result = get_metar("VABB", provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 30.0
    assert "raw_payload" not in result

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(MetarReading).where(MetarReading.icao_id == "VABB")
        ).fetchall()
    assert len(rows) == 1


def test_get_metar_refetches_when_cache_is_stale(clean_metar_readings):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    _seed_reading(fetched_at=stale_time, temperature_c=10.0)

    provider = _FakeAviationProvider(_sample_reading(temperature_c=32.0))

    result = get_metar("VABB", provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 32.0

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(MetarReading).where(MetarReading.icao_id == "VABB")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].temperature_c == 32.0


def test_get_metar_serves_stale_cache_when_live_fetch_fails(clean_metar_readings):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    _seed_reading(fetched_at=stale_time, temperature_c=10.0)

    provider = _FakeAviationProvider(None, exc=ConnectionError("network down"))

    result = get_metar("VABB", provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 10.0


def test_get_metar_normalizes_icao_id_to_uppercase(clean_metar_readings):
    _seed_reading(fetched_at=datetime.now(timezone.utc), icao_id="VABB")

    result = get_metar("vabb", provider=_RaisingProvider())

    assert result is not None
    assert result["icao_id"] == "VABB"


def test_get_metar_returns_none_when_station_has_no_data(clean_metar_readings):
    provider = _FakeAviationProvider(None)

    result = get_metar("ZZZZ", provider=provider)

    assert result is None
    assert provider.calls == 1

    with get_engine().connect() as conn:
        rows = conn.execute(select(MetarReading)).fetchall()
    assert len(rows) == 0
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_metar_service.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.aviation'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/aviation/__init__.py` (empty file).

Create `backend/app/aviation/service.py`:

```python
"""Cache-with-TTL for METAR (current airport weather) lookups by ICAO code.

Same pattern as app/weather/service.py: aviationweather.gov is a
point-queried, official, generously-rate-limited source (100 req/min, no
key), so this is the narrow spec-amended exception to WeatherGPT's
default ingestion/query split (see spec section 3's first amendment) —
not the permanent-cache pattern used for geocoding, and not the
scheduled-broadcast pattern used for SACHET alerts.
"""

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.engine import Engine

from app.db import get_engine
from app.models import MetarReading
from app.providers.aviation import AviationWeatherProvider
from app.providers.aviationweather import AviationWeatherGovProvider

logger = logging.getLogger(__name__)

_FRESHNESS_WINDOW = timedelta(minutes=25)

_RESPONSE_FIELDS = (
    "icao_id",
    "raw_metar",
    "observed_at",
    "temperature_c",
    "dewpoint_c",
    "wind_dir_deg",
    "wind_speed_kt",
    "visibility_sm",
    "flight_category",
    "station_name",
    "latitude",
    "longitude",
    "fetched_at",
)

_MUTABLE_COLUMNS = (
    "raw_metar",
    "observed_at",
    "temperature_c",
    "dewpoint_c",
    "wind_dir_deg",
    "wind_speed_kt",
    "visibility_sm",
    "flight_category",
    "station_name",
    "latitude",
    "longitude",
    "raw_payload",
    "fetched_at",
)


def _to_response(row) -> dict | None:
    if row is None:
        return None
    return {field: row[field] for field in _RESPONSE_FIELDS}


def _read_cached(engine: Engine, icao_id: str):
    with engine.connect() as conn:
        return (
            conn.execute(select(MetarReading).where(MetarReading.icao_id == icao_id))
            .mappings()
            .first()
        )


def get_metar(
    icao_id: str, provider: AviationWeatherProvider | None = None
) -> dict | None:
    normalized_icao_id = icao_id.strip().upper()

    engine = get_engine()

    row = _read_cached(engine, normalized_icao_id)

    now = datetime.now(timezone.utc)
    if row is not None and (now - row["fetched_at"]) < _FRESHNESS_WINDOW:
        return _to_response(row)

    try:
        reading = (provider or AviationWeatherGovProvider()).fetch_metar(
            normalized_icao_id
        )
    except Exception:
        if row is not None:
            logger.warning(
                "Live METAR fetch failed for %s; serving stale cache from %s",
                normalized_icao_id,
                row["fetched_at"],
            )
            return _to_response(row)
        raise

    if reading is None:
        return None

    fetched_at = datetime.now(timezone.utc)

    with engine.begin() as conn:
        stmt = pg_insert(MetarReading).values(
            icao_id=normalized_icao_id,
            raw_metar=reading.raw_metar,
            observed_at=reading.observed_at,
            temperature_c=reading.temperature_c,
            dewpoint_c=reading.dewpoint_c,
            wind_dir_deg=reading.wind_dir_deg,
            wind_speed_kt=reading.wind_speed_kt,
            visibility_sm=reading.visibility_sm,
            flight_category=reading.flight_category,
            station_name=reading.station_name,
            latitude=reading.latitude,
            longitude=reading.longitude,
            raw_payload=reading.raw_payload,
            fetched_at=fetched_at,
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=[MetarReading.icao_id],
            set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
        ).returning(MetarReading)
        updated_row = conn.execute(stmt).mappings().one()

    return _to_response(updated_row)
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_metar_service.py -v
```
Expected: PASS (6 passed).

- [ ] **Step 6: Add the endpoint**

Modify `backend/app/main.py`. Current content is:

```python
from fastapi import FastAPI, HTTPException, Query
from sqlalchemy import select

from app.db import check_db_connection, get_engine
from app.geocoding.service import geocode_place
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
def get_weather_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> dict:
    return get_weather(lat, lon)


@app.get("/geocode")
def geocode_endpoint(q: str = Query(..., min_length=1)) -> dict:
    result = geocode_place(q)
    if result is None:
        raise HTTPException(status_code=404, detail="Location not found")
    return result
```

Change it to (add the `app.aviation.service` import and the new route at the end — everything else is untouched):

```python
from fastapi import FastAPI, HTTPException, Query
from sqlalchemy import select

from app.aviation.service import get_metar
from app.db import check_db_connection, get_engine
from app.geocoding.service import geocode_place
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
def get_weather_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> dict:
    return get_weather(lat, lon)


@app.get("/geocode")
def geocode_endpoint(q: str = Query(..., min_length=1)) -> dict:
    result = geocode_place(q)
    if result is None:
        raise HTTPException(status_code=404, detail="Location not found")
    return result


@app.get("/metar")
def get_metar_endpoint(icao: str = Query(..., min_length=4, max_length=4)) -> dict:
    result = get_metar(icao)
    if result is None:
        raise HTTPException(status_code=404, detail="No METAR data for this station")
    return result
```

- [ ] **Step 7: Write the endpoint tests**

Create `backend/tests/test_metar_endpoint.py`:

```python
from datetime import datetime, timezone

from fastapi.testclient import TestClient
from sqlalchemy import insert

from app.db import get_engine
from app.main import app
from app.models import MetarReading

client = TestClient(app)


def test_metar_endpoint_returns_cached_reading(clean_metar_readings):
    with get_engine().begin() as conn:
        conn.execute(
            insert(MetarReading).values(
                icao_id="VABB",
                raw_metar="METAR VABB 060900Z 28012KT 3000 BR BKN090 30/25 Q1011 NOSIG",
                observed_at="2026-09-06T09:00:00.000Z",
                temperature_c=30.0,
                dewpoint_c=25.0,
                wind_dir_deg=280.0,
                wind_speed_kt=12.0,
                visibility_sm=1.86,
                flight_category="IFR",
                station_name="Mumbai/Shivaji Intl, MM, IN",
                latitude=19.1,
                longitude=72.859,
                raw_payload={"icaoId": "VABB"},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get("/metar", params={"icao": "VABB"})

    assert response.status_code == 200
    body = response.json()
    assert body["temperature_c"] == 30.0
    assert "raw_payload" not in body


def test_metar_endpoint_returns_404_when_not_found(monkeypatch):
    monkeypatch.setattr("app.main.get_metar", lambda icao: None)

    response = client.get("/metar", params={"icao": "ZZZZ"})

    assert response.status_code == 404


def test_metar_endpoint_rejects_wrong_length_icao_code():
    response = client.get("/metar", params={"icao": "AB"})

    assert response.status_code == 422
```

`test_metar_endpoint_returns_404_when_not_found` uses `monkeypatch` rather than a real lookup, matching the pattern already established in `test_geocode_endpoint.py` — this codebase's automated tests never make real network calls.

- [ ] **Step 8: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_metar_endpoint.py -v
```
Expected: PASS (3 passed).

- [ ] **Step 9: Manually verify against the running server (real aviationweather.gov call on first hit, cache on second)**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```
In a second terminal:
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}\n" "http://127.0.0.1:8000/metar?icao=VIDP"
curl -s -w "\nHTTP_STATUS:%{http_code}\n" "http://127.0.0.1:8000/metar?icao=VIDP"
```
Expected: both calls return `200` with the same METAR data (identical `fetched_at`, confirming the second call was cache-served). Stop the server (Ctrl+C) once confirmed. If aviationweather.gov is unreachable at verification time, note it as a concern but don't block the task.

- [ ] **Step 10: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (31 from before + 6 + 3 from this task = 40 passed).

- [ ] **Step 11: Commit**

```bash
git add backend/app/aviation/ backend/app/main.py backend/tests/conftest.py backend/tests/test_metar_service.py backend/tests/test_metar_endpoint.py
git commit -m "feat: add cache-with-TTL METAR service and GET /metar endpoint"
```
