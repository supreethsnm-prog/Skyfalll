# Nominatim Geocoding Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WeatherGPT's third provider — place-name-to-coordinate geocoding, backed by Nominatim (OpenStreetMap), with a permanent cache (not TTL-based, not scheduled-broadcast — a third distinct caching pattern from this codebase's other two providers).

**Architecture:** A `geocode_cache` Postgres table, one row per normalized query string, unique on `query`. `GET /geocode?q=..` calls `geocode_place()`, which checks the cache first: any existing row is served forever with zero network calls (place names don't move); only a genuinely new query triggers exactly one live `NominatimGeocodingProvider` call, whose result (if found) is cached and returned. This is stricter than Open-Meteo's cache-with-TTL pattern — there is no staleness check at all — because Nominatim's usage policy requires client-side caching and caps regular/scripted use at 4 requests/minute, which this codebase must respect operationally, not just as an optimization.

**Tech Stack:** FastAPI, SQLAlchemy 2.x + Alembic (already set up), Postgres (`JSONB`, `INSERT ... ON CONFLICT DO NOTHING ... RETURNING`), httpx with `httpx.MockTransport` for tests.

**Spec:** `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md` (§3 already mentions geocoding caching)

## Global Constraints

- Backend is FastAPI + PostgreSQL only — no other framework or database engine.
- Nominatim's usage policy (the free public instance this provider calls) requires: (a) a descriptive User-Agent identifying the application on every request — never a default library User-Agent; (b) client-side caching of results; (c) respecting a 4 requests/minute ceiling for regular/scripted use. This plan's caching design exists to satisfy (b) and keep (c) realistic, not just for performance — do not weaken the "cache forever, never re-fetch an existing query" design.
- Unlike `app/weather/service.py` (cache-with-20-minute-TTL) and `app/ingestion/alerts.py` (scheduled broadcast, no per-query caching decision), this is a THIRD pattern: permanent cache, lookup-once-per-query. Do not copy the weather service's freshness-window logic here — there is no freshness window.
- Every response returned to a client must exclude `raw_payload`, same rule as every other query endpoint in this codebase.
- Every task ends in a state that actually runs and is verified before the next task starts.
- This machine: `python` on PATH (not `python3`); `docker` NOT on PATH — use the full path `/c/Users/ACER/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe` if any docker command is needed. Postgres already running on `127.0.0.1:5432` (shared across worktrees) — confirm with `"$DOCKER" ps`, don't assume.

---

## File Structure

```
backend/
├── alembic/versions/<rev>_create_geocode_cache_table.py   # generated
├── app/
│   ├── models.py                       # modified: add GeocodeCache
│   ├── main.py                         # modified: add GET /geocode
│   ├── providers/
│   │   ├── geocoding.py                # new: GeocodeResultData, GeocodingProvider protocol
│   │   └── nominatim.py                # new: NominatimGeocodingProvider
│   └── geocoding/
│       ├── __init__.py                 # new, empty
│       └── service.py                  # new: geocode_place()
└── tests/
    ├── conftest.py                     # modified: add clean_geocode_cache fixture
    ├── test_geocode_cache_table_schema.py   # new
    ├── test_nominatim_provider.py       # new
    ├── test_geocoding_service.py         # new
    └── test_geocode_endpoint.py          # new
```

---

### Task 1: `geocode_cache` table

**Files:**
- Modify: `backend/app/models.py`
- Create: `backend/alembic/versions/<rev>_create_geocode_cache_table.py` (generated)
- Test: `backend/tests/test_geocode_cache_table_schema.py`

**Interfaces:**
- Consumes: `app.db:get_engine()`; `app.models:Base` (already exists).
- Produces: `app.models:GeocodeCache`, a mapped class for table `geocode_cache` with columns: `id` (int, PK), `query` (string, unique, indexed, not null — the normalized/lowercased/stripped cache key), `display_name` (string, not null), `latitude` (float, not null), `longitude` (float, not null), `country` (string, nullable), `state` (string, nullable), `raw_payload` (JSONB, not null), `fetched_at` (timezone-aware datetime, not null — purely informational; nothing ever checks it for staleness). Task 3 imports `GeocodeCache` from `app.models` and relies on this exact column set and the single-column unique constraint on `query`.

- [ ] **Step 1: Add the model**

Current `backend/app/models.py` ends with the `WeatherReading` class (last line is `fetched_at = Column(DateTime(timezone=True), nullable=False)` closing that class). Append this new class at the end of the file (the `Alert` and `WeatherReading` classes are untouched):

```python
class GeocodeCache(Base):
    __tablename__ = "geocode_cache"

    id = Column(Integer, primary_key=True)
    query = Column(String, unique=True, nullable=False, index=True)
    display_name = Column(String, nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    country = Column(String, nullable=True)
    state = Column(String, nullable=True)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
```

No new imports are needed — `Column`, `DateTime`, `Float`, `Integer`, `String`, `JSONB` are already imported at the top of the file.

- [ ] **Step 2: Write the failing test**

Create `backend/tests/test_geocode_cache_table_schema.py`:

```python
from sqlalchemy import inspect

from app.db import get_engine


def test_geocode_cache_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "geocode_cache" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("geocode_cache")}
    assert columns == {
        "id",
        "query",
        "display_name",
        "latitude",
        "longitude",
        "country",
        "state",
        "raw_payload",
        "fetched_at",
    }


def test_geocode_cache_has_unique_constraint_on_query():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("geocode_cache")
    matching = [c for c in constraints if c["column_names"] == ["query"]]
    assert len(matching) == 1
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_geocode_cache_table_schema.py -v
```
Expected: FAIL — `assert "geocode_cache" in inspector.get_table_names()` fails, table doesn't exist yet.

- [ ] **Step 4: Generate and review the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic revision --autogenerate -m "create geocode_cache table"
```
Expected: creates a file under `backend/alembic/versions/`. Open it and confirm `upgrade()` creates a table named `geocode_cache` with all 9 columns from Step 1 and a unique constraint/index on `query` alone (not composite — this table has no composite key, unlike `weather_readings`). Also confirm `upgrade()`/`downgrade()` do NOT touch `alerts` or `weather_readings` — if they do, stop and report BLOCKED rather than applying it.

- [ ] **Step 5: Apply the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic upgrade head
```
Expected: output ends with `Running upgrade <weather_readings-rev> -> <new-rev>, create geocode_cache table`, no errors.

- [ ] **Step 6: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_geocode_cache_table_schema.py -v
```
Expected: both PASS.

- [ ] **Step 7: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (17 existing + 2 from this task = 19 passed).

- [ ] **Step 8: Commit**

```bash
git add backend/app/models.py backend/alembic/versions/ backend/tests/test_geocode_cache_table_schema.py
git commit -m "feat: add geocode_cache table"
```

---

### Task 2: `GeocodingProvider` protocol + `NominatimGeocodingProvider`

**Files:**
- Create: `backend/app/providers/geocoding.py`
- Create: `backend/app/providers/nominatim.py`
- Test: `backend/tests/test_nominatim_provider.py`

**Interfaces:**
- Consumes: nothing from Task 1 (this task never touches the database).
- Produces: `app.providers.geocoding:GeocodeResultData` (a dataclass with fields `query: str`, `display_name: str`, `latitude: float`, `longitude: float`, `country: str | None`, `state: str | None`, `raw_payload: dict`). `app.providers.geocoding:GeocodingProvider` (a `Protocol` with `geocode(self, query: str) -> GeocodeResultData | None`, where `None` means "no matches found" — not an error, not an exception). `app.providers.nominatim:NominatimGeocodingProvider`, constructible as `NominatimGeocodingProvider()` (real network, self-closing client) or `NominatimGeocodingProvider(client=some_httpx_client)` (injected client for tests). Task 3 imports `GeocodingProvider`/`GeocodeResultData` from `app.providers.geocoding` and `NominatimGeocodingProvider` from `app.providers.nominatim`.

**Two critical details:**
1. Nominatim returns `lat`/`lon` as **strings** (e.g. `"19.0549990"`) — these must be converted with `float()`, not stored/compared as strings.
2. Nominatim's `"address"` object has no fixed schema — its keys vary by place type. Access every field inside it with `.get()`, never `["key"]` directly, except `display_name`, `lat`, `lon` at the top level of a result, which are always present when a result exists at all.

- [ ] **Step 1: Create the canonical GeocodeResultData shape and the provider protocol**

Create `backend/app/providers/geocoding.py`:

```python
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class GeocodeResultData:
    query: str
    display_name: str
    latitude: float
    longitude: float
    country: str | None
    state: str | None
    raw_payload: dict[str, Any]


class GeocodingProvider(Protocol):
    def geocode(self, query: str) -> GeocodeResultData | None: ...
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_nominatim_provider.py`:

```python
import httpx

from app.providers.nominatim import NominatimGeocodingProvider

FOUND_RESPONSE = [
    {
        "place_id": 248916270,
        "licence": "Data © OpenStreetMap contributors, ODbL 1.0. http://osm.org/copyright",
        "osm_type": "node",
        "osm_id": 16173235,
        "lat": "19.0549990",
        "lon": "72.8692035",
        "category": "place",
        "type": "city",
        "place_rank": 16,
        "importance": 0.7153284564294777,
        "addresstype": "city",
        "name": "Mumbai",
        "display_name": "Mumbai, Mumbai Suburban District, Maharashtra, 400051, India",
        "address": {
            "city": "Mumbai",
            "state_district": "Mumbai Suburban District",
            "state": "Maharashtra",
            "ISO3166-2-lvl4": "IN-MH",
            "postcode": "400051",
            "country": "India",
            "country_code": "in",
        },
        "boundingbox": ["18.8949990", "19.2149990", "72.7092035", "73.0292035"],
    }
]

NOT_FOUND_RESPONSE: list = []


def _found_handler(request: httpx.Request) -> httpx.Response:
    assert request.headers["User-Agent"] == "WeatherGPT/0.1 (SIH 2026 hackathon project)"
    return httpx.Response(200, json=FOUND_RESPONSE)


def _not_found_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=NOT_FOUND_RESPONSE)


def test_geocode_returns_normalized_result_when_found():
    client = httpx.Client(transport=httpx.MockTransport(_found_handler))
    provider = NominatimGeocodingProvider(client=client)

    result = provider.geocode("mumbai")

    assert result is not None
    assert result.query == "mumbai"
    assert result.display_name == (
        "Mumbai, Mumbai Suburban District, Maharashtra, 400051, India"
    )
    assert result.latitude == 19.0549990
    assert result.longitude == 72.8692035
    assert result.country == "India"
    assert result.state == "Maharashtra"
    assert result.raw_payload == FOUND_RESPONSE[0]


def test_geocode_returns_none_when_not_found():
    client = httpx.Client(transport=httpx.MockTransport(_not_found_handler))
    provider = NominatimGeocodingProvider(client=client)

    result = provider.geocode("zzznonexistentplacexyz123456")

    assert result is None
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_nominatim_provider.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.providers.nominatim'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/providers/nominatim.py`:

```python
import httpx

from app.providers.geocoding import GeocodeResultData

NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org/search"
_USER_AGENT = "WeatherGPT/0.1 (SIH 2026 hackathon project)"


class NominatimGeocodingProvider:
    def __init__(self, base_url: str = NOMINATIM_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def geocode(self, query: str) -> GeocodeResultData | None:
        try:
            response = self._client.get(
                self._base_url,
                params={
                    "q": query,
                    "format": "jsonv2",
                    "limit": 1,
                    "addressdetails": 1,
                },
                headers={"User-Agent": _USER_AGENT},
            )
            response.raise_for_status()
            results = response.json()
            if not results:
                return None

            result = results[0]
            address = result.get("address", {})
            return GeocodeResultData(
                query=query,
                display_name=result["display_name"],
                latitude=float(result["lat"]),
                longitude=float(result["lon"]),
                country=address.get("country"),
                state=address.get("state"),
                raw_payload=result,
            )
        finally:
            if self._owns_client:
                self._client.close()
```

Setting the `User-Agent` header on the `.get()` call itself (rather than only at client-construction time) guarantees the correct header is sent regardless of whether the client was self-constructed or injected — this is what the test's `_found_handler` asserts.

- [ ] **Step 5: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_nominatim_provider.py -v
```
Expected: PASS (2 passed).

- [ ] **Step 6: Manually verify against the real Nominatim endpoint (one-off, not part of the automated suite)**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -c "
from app.providers.nominatim import NominatimGeocodingProvider
result = NominatimGeocodingProvider().geocode('Chennai, India')
print(result)
"
```
Expected: prints a `GeocodeResultData` with real coordinates for Chennai and a real `display_name`. This is a real request to the public Nominatim instance with the real `WeatherGPT/0.1 (SIH 2026 hackathon project)` User-Agent — run it once, not in a loop, per the usage policy. If this fails (network error, changed response shape), note it in your report as a concern but do not block the task on it — the mocked tests are what's graded.

- [ ] **Step 7: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (19 from before + 2 from this task = 21 passed).

- [ ] **Step 8: Commit**

```bash
git add backend/app/providers/geocoding.py backend/app/providers/nominatim.py backend/tests/test_nominatim_provider.py
git commit -m "feat: add GeocodingProvider protocol and NominatimGeocodingProvider"
```

---

### Task 3: `geocode_place()` permanent-cache service + `GET /geocode` endpoint

**Files:**
- Create: `backend/app/geocoding/__init__.py` (empty)
- Create: `backend/app/geocoding/service.py`
- Modify: `backend/tests/conftest.py` (add `clean_geocode_cache` fixture)
- Modify: `backend/app/main.py` (add `GET /geocode`)
- Test: `backend/tests/test_geocoding_service.py`
- Test: `backend/tests/test_geocode_endpoint.py`

**Interfaces:**
- Consumes: `app.providers.geocoding:GeocodingProvider`, `app.providers.geocoding:GeocodeResultData` (Task 2); `app.providers.nominatim:NominatimGeocodingProvider` (Task 2); `app.models:GeocodeCache` (Task 1); `app.db:get_engine()`.
- Produces: `app.geocoding.service:geocode_place(query: str, provider: GeocodingProvider | None = None) -> dict | None`. Returns `None` if the place cannot be found (nothing is written to the cache in that case). On success, the returned dict has keys `query`, `display_name`, `latitude`, `longitude`, `country`, `state`, `fetched_at` — it never includes `raw_payload`.

- [ ] **Step 1: Add the test fixture for cleaning up test data**

`backend/tests/conftest.py` currently starts with:
```python
import pytest
from sqlalchemy import delete

from app.config import get_settings
from app.db import get_engine
from app.models import Alert, WeatherReading
from app.providers.warning import AlertData
```
Change the `from app.models import Alert, WeatherReading` line to `from app.models import Alert, GeocodeCache, WeatherReading` (add the one new name, don't add a second import line).

Then append this fixture to the end of the file (keep existing fixtures untouched):

```python
@pytest.fixture
def clean_geocode_cache():
    yield
    with get_engine().begin() as conn:
        conn.execute(delete(GeocodeCache))
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_geocoding_service.py`:

```python
from sqlalchemy import select

from app.db import get_engine
from app.geocoding.service import geocode_place
from app.models import GeocodeCache
from app.providers.geocoding import GeocodeResultData


class _RaisingProvider:
    def geocode(self, query):
        raise AssertionError("provider should not be called on a cache hit")


class _FakeGeocodingProvider:
    def __init__(self, result: GeocodeResultData | None):
        self._result = result
        self.calls = 0
        self.received_query = None

    def geocode(self, query):
        self.calls += 1
        self.received_query = query
        return self._result


def _sample_result(query="mumbai") -> GeocodeResultData:
    return GeocodeResultData(
        query=query,
        display_name="Mumbai, Maharashtra, India",
        latitude=19.0549990,
        longitude=72.8692035,
        country="India",
        state="Maharashtra",
        raw_payload={"name": "Mumbai"},
    )


def test_geocode_place_returns_cached_row_without_calling_provider(
    clean_geocode_cache,
):
    geocode_place("Mumbai", provider=_FakeGeocodingProvider(_sample_result()))

    result = geocode_place("Mumbai", provider=_RaisingProvider())

    assert result is not None
    assert result["display_name"] == "Mumbai, Maharashtra, India"
    assert "raw_payload" not in result


def test_geocode_place_normalizes_query_before_cache_lookup(clean_geocode_cache):
    geocode_place("  Mumbai  ", provider=_FakeGeocodingProvider(_sample_result()))

    result = geocode_place("MUMBAI", provider=_RaisingProvider())

    assert result is not None
    assert result["query"] == "mumbai"


def test_geocode_place_fetches_and_caches_on_missing_row(clean_geocode_cache):
    provider = _FakeGeocodingProvider(_sample_result())

    result = geocode_place("Mumbai", provider=provider)

    assert provider.calls == 1
    assert provider.received_query == "mumbai"
    assert result is not None
    assert result["latitude"] == 19.0549990

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(GeocodeCache).where(GeocodeCache.query == "mumbai")
        ).fetchall()
    assert len(rows) == 1


def test_geocode_place_returns_none_and_caches_nothing_when_not_found(
    clean_geocode_cache,
):
    provider = _FakeGeocodingProvider(None)

    result = geocode_place("zzznonexistentplacexyz123456", provider=provider)

    assert result is None
    assert provider.calls == 1

    with get_engine().connect() as conn:
        rows = conn.execute(select(GeocodeCache)).fetchall()
    assert len(rows) == 0
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_geocoding_service.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.geocoding'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/geocoding/__init__.py` (empty file).

Create `backend/app/geocoding/service.py`:

```python
"""Permanent cache for geocoding lookups.

Place names don't move — unlike weather (see app/weather/service.py's
cache-with-TTL pattern), a geocode result is cached forever once found,
with no freshness check. This also respects Nominatim's usage policy,
which requires client-side caching and caps regular/scripted use at 4
requests/minute; see spec section 3.
"""

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import GeocodeCache
from app.providers.geocoding import GeocodingProvider
from app.providers.nominatim import NominatimGeocodingProvider

_RESPONSE_FIELDS = (
    "query",
    "display_name",
    "latitude",
    "longitude",
    "country",
    "state",
    "fetched_at",
)


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def geocode_place(
    query: str, provider: GeocodingProvider | None = None
) -> dict | None:
    normalized_query = query.strip().lower()

    engine = get_engine()

    with engine.connect() as conn:
        row = (
            conn.execute(
                select(GeocodeCache).where(GeocodeCache.query == normalized_query)
            )
            .mappings()
            .first()
        )

    if row is not None:
        return _to_response(row)

    result = (provider or NominatimGeocodingProvider()).geocode(normalized_query)
    if result is None:
        return None

    fetched_at = datetime.now(timezone.utc)

    with engine.begin() as conn:
        stmt = pg_insert(GeocodeCache).values(
            query=normalized_query,
            display_name=result.display_name,
            latitude=result.latitude,
            longitude=result.longitude,
            country=result.country,
            state=result.state,
            raw_payload=result.raw_payload,
            fetched_at=fetched_at,
        )
        stmt = stmt.on_conflict_do_nothing(
            index_elements=[GeocodeCache.query]
        ).returning(GeocodeCache)
        inserted_row = conn.execute(stmt).mappings().first()

    if inserted_row is not None:
        return _to_response(inserted_row)

    # A concurrent request already inserted this query between our cache
    # check and this insert. Don't overwrite it — re-read what's there.
    with engine.connect() as conn:
        row = (
            conn.execute(
                select(GeocodeCache).where(GeocodeCache.query == normalized_query)
            )
            .mappings()
            .first()
        )
    return _to_response(row)
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_geocoding_service.py -v
```
Expected: PASS (4 passed).

- [ ] **Step 6: Add the endpoint**

Modify `backend/app/main.py`. Current content is:

```python
from fastapi import FastAPI, Query
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
def get_weather_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> dict:
    return get_weather(lat, lon)
```

Change it to (add the `HTTPException` import, the `app.geocoding.service` import, and the new route at the end — everything else is untouched):

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

- [ ] **Step 7: Write the endpoint tests**

Create `backend/tests/test_geocode_endpoint.py`:

```python
from fastapi.testclient import TestClient

from app.geocoding.service import geocode_place
from app.main import app
from app.providers.geocoding import GeocodeResultData

client = TestClient(app)


class _FakeGeocodingProvider:
    def __init__(self, result):
        self._result = result

    def geocode(self, query):
        return self._result


def test_geocode_endpoint_returns_cached_result(clean_geocode_cache):
    geocode_place(
        "Mumbai",
        provider=_FakeGeocodingProvider(
            GeocodeResultData(
                query="mumbai",
                display_name="Mumbai, Maharashtra, India",
                latitude=19.0549990,
                longitude=72.8692035,
                country="India",
                state="Maharashtra",
                raw_payload={"name": "Mumbai"},
            )
        ),
    )

    response = client.get("/geocode", params={"q": "Mumbai"})

    assert response.status_code == 200
    body = response.json()
    assert body["display_name"] == "Mumbai, Maharashtra, India"
    assert "raw_payload" not in body


def test_geocode_endpoint_returns_404_when_not_found(monkeypatch):
    monkeypatch.setattr("app.main.geocode_place", lambda q: None)

    response = client.get(
        "/geocode", params={"q": "zzznonexistentplacexyz123456notcached"}
    )

    assert response.status_code == 404
```

`test_geocode_endpoint_returns_404_when_not_found` uses `monkeypatch.setattr` on the `geocode_place` name as imported into `app.main` (not the real function) so this test never touches the network or the database — consistent with every other automated test in this codebase. The real provider's "not found" behavior is already proven by Task 2's `test_geocode_returns_none_when_not_found` (mocked) and the service layer's `test_geocode_place_returns_none_and_caches_nothing_when_not_found` — this test only needs to prove the endpoint correctly turns a `None` into a 404, which doesn't require a real lookup. Do not query a real nonsense string against Nominatim in a test that runs every time the suite runs — repeatedly sending the identical query on every test run would itself violate the "no repeated identical queries" clause of Nominatim's usage policy.

- [ ] **Step 8: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_geocode_endpoint.py -v
```
Expected: PASS (2 passed). Neither test touches the network or requires connectivity.

- [ ] **Step 9: Manually verify against the running server**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```
In a second terminal:
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}\n" "http://127.0.0.1:8000/geocode?q=Bengaluru"
curl -s -w "\nHTTP_STATUS:%{http_code}\n" "http://127.0.0.1:8000/geocode?q=Bengaluru"
```
Expected: both calls return `200` with the same geocode data (the second call served from cache, no new Nominatim request). Stop the server (Ctrl+C) once confirmed.

- [ ] **Step 10: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (21 from before + 4 + 2 from this task = 27 passed).

- [ ] **Step 11: Commit**

```bash
git add backend/app/geocoding/ backend/app/main.py backend/tests/conftest.py backend/tests/test_geocoding_service.py backend/tests/test_geocode_endpoint.py
git commit -m "feat: add permanent geocoding cache service and GET /geocode endpoint"
```
