# INCOIS Marine Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WeatherGPT's fifth provider — Potential Fishing Zone (PFZ) marine advisories, backed by INCOIS's public GeoServer WFS, using the SAME scheduled-ingestion pattern as SACHET alerts (not either of the two point-query caching patterns used by weather/aviation or geocoding).

**Architecture:** PFZ data is a bounded feature collection (65 line geometries covering the Indian coastline, verified live), not a value queried per-coordinate or per-code — there is nothing to look up "at" a point, and no meaningful per-query cache key. This is architecturally identical to SACHET: fetch the whole collection on a schedule/trigger, upsert every feature into Postgres keyed by its stable WFS feature id, and serve a query endpoint that reads only from Postgres. `POST /internal/ingest/marine` triggers ingestion (no scheduler yet, same as alerts); `GET /marine/pfz-zones` reads the cached rows.

**Tech Stack:** FastAPI, SQLAlchemy 2.x + Alembic (already set up), Postgres (`JSONB` for the geometry and raw payload, `INSERT ... ON CONFLICT DO UPDATE`), httpx with `httpx.MockTransport` for tests.

**Spec:** `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md` (Marine section names INCOIS's WFS `PFZ_Automation:pfzlines` layer as the verified source)

## Global Constraints

- Backend is FastAPI + PostgreSQL only — no other framework or database engine.
- This is the scheduled-ingestion pattern (same as `app/ingestion/alerts.py`), NOT a cache-with-TTL point-query pattern (like `app/weather/service.py`/`app/aviation/service.py`) and NOT a permanent per-query cache (like `app/geocoding/service.py`) — there is no per-request cache key here, the whole collection is refreshed together. Do not add a freshness-window check to the query endpoint.
- The query path (`GET /marine/pfz-zones`) must never call the provider directly — only the ingestion trigger may.
- Unlike every other provider's response so far, `geometry` IS the substantive content being requested here (the line coordinates a client needs to render a fishing-zone boundary) — it must be INCLUDED in query responses. `raw_payload` (the full untransformed WFS feature, kept for forward-compat/debugging) is still excluded from every response, same rule as everywhere else in this codebase.
- Per-feature parsing failures must be isolated in the PROVIDER layer (skip and log the one bad feature, keep the rest) — the same lesson `app/providers/sachet.py` already had to learn after its own final review, applied here from the start. The ingestion function itself receives an already-filtered list and does not need its own per-item try/except.
- The upsert's `set_` clause must be derived from the model's own columns (`PfzZone.__table__.columns`), not hand-listed — the pattern already established in `app/ingestion/alerts.py` after an earlier sprint's fix, applied here from the start.
- Every task ends in a state that actually runs and is verified before the next task starts.
- This machine: `python` on PATH (not `python3`); `docker` NOT on PATH — use the full path `/c/Users/ACER/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe` if any docker command is needed. Postgres already running on `127.0.0.1:5432` (shared across worktrees) — confirm with `"$DOCKER" ps`, don't assume.

---

## File Structure

```
backend/
├── alembic/versions/<rev>_create_pfz_zones_table.py   # generated
├── app/
│   ├── models.py                       # modified: add PfzZone
│   ├── main.py                         # modified: add POST /internal/ingest/marine, GET /marine/pfz-zones
│   ├── providers/
│   │   ├── marine.py                   # new: PfzZoneData, MarineProvider protocol
│   │   └── incois.py                   # new: INCOISMarineProvider
│   └── ingestion/
│       └── marine.py                   # new: ingest_pfz_zones()
└── tests/
    ├── conftest.py                     # modified: add clean_pfz_zones fixture
    ├── test_pfz_zones_table_schema.py   # new
    ├── test_incois_provider.py          # new
    ├── test_ingest_marine.py            # new
    └── test_marine_endpoint.py          # new
```

---

### Task 1: `pfz_zones` table

**Files:**
- Modify: `backend/app/models.py`
- Create: `backend/alembic/versions/<rev>_create_pfz_zones_table.py` (generated)
- Test: `backend/tests/test_pfz_zones_table_schema.py`

**Interfaces:**
- Consumes: `app.db:get_engine()`; `app.models:Base` (already exists).
- Produces: `app.models:PfzZone`, a mapped class for table `pfz_zones` with columns: `id` (int, PK), `external_id` (string, unique, indexed, not null — the WFS feature id, e.g. `"pfzlines.1"`), `category` (string, nullable — e.g. `"ghrsst"`), `sector_boundary` (integer, nullable), `sector_name` (string, nullable — can be an empty string in real data), `julian_day` (string, nullable — kept as the source's raw string, e.g. `"248"`, not parsed into a number or date), `serial_number` (string, nullable — e.g. `"001"`), `year` (integer, nullable), `uid` (integer, nullable — a combined year+day+serial identifier from the source, e.g. `2021248001`; informational only, `external_id` is the real key), `length_km` (float, nullable), `geometry` (JSONB, not null — the full GeoJSON geometry object, e.g. `{"type": "MultiLineString", "coordinates": [...]}`), `raw_payload` (JSONB, not null — the complete untransformed WFS feature), `fetched_at` (timezone-aware datetime, not null). Single-column unique constraint on `external_id`. Task 3 and Task 4 import `PfzZone` from `app.models` and rely on this exact column set.

- [ ] **Step 1: Add the model**

Current `backend/app/models.py` ends with the `MetarReading` class (last line is `fetched_at = Column(DateTime(timezone=True), nullable=False)` closing that class). Append this new class at the end of the file (the other four classes are untouched):

```python
class PfzZone(Base):
    __tablename__ = "pfz_zones"

    id = Column(Integer, primary_key=True)
    external_id = Column(String, unique=True, nullable=False)
    category = Column(String, nullable=True)
    sector_boundary = Column(Integer, nullable=True)
    sector_name = Column(String, nullable=True)
    julian_day = Column(String, nullable=True)
    serial_number = Column(String, nullable=True)
    year = Column(Integer, nullable=True)
    uid = Column(Integer, nullable=True)
    length_km = Column(Float, nullable=True)
    geometry = Column(JSONB, nullable=False)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
```

No new imports are needed — `Column`, `DateTime`, `Float`, `Integer`, `String`, `JSONB` are already imported at the top of the file. `external_id` uses `unique=True` alone (NOT `unique=True, index=True` together) — that combination was found in an earlier sprint to produce a Postgres unique INDEX rather than a table-level UNIQUE CONSTRAINT, which `get_unique_constraints()` (used in Step 2's test) cannot see.

- [ ] **Step 2: Write the failing test**

Create `backend/tests/test_pfz_zones_table_schema.py`:

```python
from sqlalchemy import inspect

from app.db import get_engine


def test_pfz_zones_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "pfz_zones" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("pfz_zones")}
    assert columns == {
        "id",
        "external_id",
        "category",
        "sector_boundary",
        "sector_name",
        "julian_day",
        "serial_number",
        "year",
        "uid",
        "length_km",
        "geometry",
        "raw_payload",
        "fetched_at",
    }


def test_pfz_zones_has_unique_constraint_on_external_id():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("pfz_zones")
    matching = [c for c in constraints if c["column_names"] == ["external_id"]]
    assert len(matching) == 1
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_pfz_zones_table_schema.py -v
```
Expected: FAIL — table doesn't exist yet.

- [ ] **Step 4: Generate and review the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic revision --autogenerate -m "create pfz_zones table"
```
Expected: creates a file under `backend/alembic/versions/`. Open it and confirm `upgrade()` creates a table named `pfz_zones` with all 13 columns from Step 1 and a unique constraint on `external_id` alone. Also confirm `upgrade()`/`downgrade()` do NOT touch `alerts`, `weather_readings`, `geocode_cache`, or `metar_readings` — if they do, stop and report BLOCKED rather than applying it.

- [ ] **Step 5: Apply the migration**

Run (from `backend/`):
```bash
./.venv/Scripts/python.exe -m alembic upgrade head
```
Expected: output ends with `Running upgrade <metar_readings-rev> -> <new-rev>, create pfz_zones table`, no errors.

- [ ] **Step 6: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_pfz_zones_table_schema.py -v
```
Expected: both PASS.

- [ ] **Step 7: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (43 existing + 2 from this task = 45 passed).

- [ ] **Step 8: Commit**

```bash
git add backend/app/models.py backend/alembic/versions/ backend/tests/test_pfz_zones_table_schema.py
git commit -m "feat: add pfz_zones table"
```

---

### Task 2: `MarineProvider` protocol + `INCOISMarineProvider`

**Files:**
- Create: `backend/app/providers/marine.py`
- Create: `backend/app/providers/incois.py`
- Test: `backend/tests/test_incois_provider.py`

**Interfaces:**
- Consumes: nothing from Task 1 (this task never touches the database).
- Produces: `app.providers.marine:PfzZoneData` (a dataclass with fields `external_id: str`, `category: str | None`, `sector_boundary: int | None`, `sector_name: str | None`, `julian_day: str | None`, `serial_number: str | None`, `year: int | None`, `uid: int | None`, `length_km: float | None`, `geometry: dict`, `raw_payload: dict`). `app.providers.marine:MarineProvider` (a `Protocol` with `fetch_pfz_zones(self) -> list[PfzZoneData]`). `app.providers.incois:INCOISMarineProvider`, constructible as `INCOISMarineProvider()` (real network, self-closing client) or `INCOISMarineProvider(client=some_httpx_client)` (injected for tests). Task 3 imports `MarineProvider`/`PfzZoneData` from `app.providers.marine` and `INCOISMarineProvider` from `app.providers.incois`.

**Verified live (real WFS GetFeature call during planning):**
- Base URL: `https://incois.gov.in/geoserver/PFZ_Automation/ows`
- Query params: `service=WFS`, `version=2.0.0`, `request=GetFeature`, `typeNames=PFZ_Automation:pfzlines`, `outputFormat=application/json`
- Real response shape: `{"type": "FeatureCollection", "totalFeatures": 65, "features": [{"type": "Feature", "id": "pfzlines.1", "geometry": {"type": "MultiLineString", "coordinates": [[[68.436..., 22.770...], ...]]}, "properties": {"Category": "ghrsst", "SECTORBOUN": 2, "SECTORBO_1": 1, "SECTORNAME": "", "Julian_day": "248", "Sno": "001", "Year": 2021, "UID": 2021248001, "Length": 45.9872025145}}, ...]}`
- No API key needed — this is a public, unauthenticated GeoServer, same reverse-engineered/undocumented risk profile as SACHET (no published API contract, could change without notice) — treat it with the same isolation discipline.
- A feature's `properties` object could theoretically be missing a key or hold an unexpected type for any given feature (this is an undocumented government service, not a versioned contract) — each feature must be parsed defensively, and a malformed individual feature must be skipped (logged, not raised) without discarding the other 64.

- [ ] **Step 1: Create the canonical PfzZoneData shape and the provider protocol**

Create `backend/app/providers/marine.py`:

```python
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class PfzZoneData:
    external_id: str
    category: str | None
    sector_boundary: int | None
    sector_name: str | None
    julian_day: str | None
    serial_number: str | None
    year: int | None
    uid: int | None
    length_km: float | None
    geometry: dict[str, Any]
    raw_payload: dict[str, Any]


class MarineProvider(Protocol):
    def fetch_pfz_zones(self) -> list[PfzZoneData]: ...
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_incois_provider.py`:

```python
import httpx

from app.providers.incois import INCOISMarineProvider

FOUND_RESPONSE = {
    "type": "FeatureCollection",
    "totalFeatures": 2,
    "features": [
        {
            "type": "Feature",
            "id": "pfzlines.1",
            "geometry": {
                "type": "MultiLineString",
                "coordinates": [[[68.4367, 22.7704], [68.4363, 22.7694]]],
            },
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 2,
                "SECTORBO_1": 1,
                "SECTORNAME": "",
                "Julian_day": "248",
                "Sno": "001",
                "Year": 2021,
                "UID": 2021248001,
                "Length": 45.9872025145,
            },
        },
        {
            "type": "Feature",
            "id": "pfzlines.2",
            "geometry": {
                "type": "MultiLineString",
                "coordinates": [[[70.1, 20.5], [70.2, 20.6]]],
            },
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 3,
                "SECTORBO_1": 1,
                "SECTORNAME": "West Coast",
                "Julian_day": "248",
                "Sno": "002",
                "Year": 2021,
                "UID": 2021248002,
                "Length": 30.5,
            },
        },
    ],
}

MALFORMED_RESPONSE = {
    "type": "FeatureCollection",
    "totalFeatures": 2,
    "features": [
        {
            "type": "Feature",
            "id": "pfzlines.3",
            "geometry": {"type": "MultiLineString", "coordinates": [[[1.0, 2.0]]]},
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 1,
                "SECTORBO_1": 1,
                "SECTORNAME": "",
                "Julian_day": "100",
                "Sno": "003",
                "Year": 2021,
                "UID": 2021100003,
                "Length": 10.0,
            },
        },
        {
            # Missing "geometry" entirely — malformed, must be skipped, not raise.
            "type": "Feature",
            "id": "pfzlines.4",
            "properties": {
                "Category": "ghrsst",
                "SECTORBOUN": 1,
                "SECTORBO_1": 1,
                "SECTORNAME": "",
                "Julian_day": "100",
                "Sno": "004",
                "Year": 2021,
                "UID": 2021100004,
                "Length": 5.0,
            },
        },
    ],
}


def _found_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=FOUND_RESPONSE)


def _malformed_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=MALFORMED_RESPONSE)


def test_fetch_pfz_zones_normalizes_all_features():
    client = httpx.Client(transport=httpx.MockTransport(_found_handler))
    provider = INCOISMarineProvider(client=client)

    zones = provider.fetch_pfz_zones()

    assert len(zones) == 2
    first = next(z for z in zones if z.external_id == "pfzlines.1")
    assert first.category == "ghrsst"
    assert first.sector_boundary == 2
    assert first.sector_name == ""
    assert first.julian_day == "248"
    assert first.serial_number == "001"
    assert first.year == 2021
    assert first.uid == 2021248001
    assert first.length_km == 45.9872025145
    assert first.geometry == FOUND_RESPONSE["features"][0]["geometry"]
    assert first.raw_payload == FOUND_RESPONSE["features"][0]

    second = next(z for z in zones if z.external_id == "pfzlines.2")
    assert second.sector_name == "West Coast"


def test_fetch_pfz_zones_skips_malformed_feature_without_failing_the_batch():
    client = httpx.Client(transport=httpx.MockTransport(_malformed_handler))
    provider = INCOISMarineProvider(client=client)

    zones = provider.fetch_pfz_zones()

    assert len(zones) == 1
    assert zones[0].external_id == "pfzlines.3"
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_incois_provider.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.providers.incois'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/providers/incois.py`:

```python
import logging

import httpx

from app.providers.marine import PfzZoneData

INCOIS_BASE_URL = "https://incois.gov.in/geoserver/PFZ_Automation/ows"

logger = logging.getLogger(__name__)


def _normalize_feature(feature: dict) -> PfzZoneData:
    properties = feature.get("properties", {})
    return PfzZoneData(
        external_id=feature["id"],
        category=properties.get("Category"),
        sector_boundary=properties.get("SECTORBOUN"),
        sector_name=properties.get("SECTORNAME"),
        julian_day=properties.get("Julian_day"),
        serial_number=properties.get("Sno"),
        year=properties.get("Year"),
        uid=properties.get("UID"),
        length_km=properties.get("Length"),
        geometry=feature["geometry"],
        raw_payload=feature,
    )


class INCOISMarineProvider:
    def __init__(self, base_url: str = INCOIS_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=15.0)

    def fetch_pfz_zones(self) -> list[PfzZoneData]:
        try:
            response = self._client.get(
                self._base_url,
                params={
                    "service": "WFS",
                    "version": "2.0.0",
                    "request": "GetFeature",
                    "typeNames": "PFZ_Automation:pfzlines",
                    "outputFormat": "application/json",
                },
            )
            response.raise_for_status()
            payload = response.json()

            zones = []
            for feature in payload.get("features", []):
                try:
                    zones.append(_normalize_feature(feature))
                except (KeyError, TypeError) as exc:
                    logger.warning(
                        "Skipping malformed PFZ feature %r: %s",
                        feature.get("id"),
                        exc,
                    )
            return zones
        finally:
            if self._owns_client:
                self._client.close()
```

`_normalize_feature` accesses `feature["id"]` and `feature["geometry"]` with direct indexing (they're required — a feature with neither is not a usable zone) inside the per-feature `try/except`, so a missing key is caught and logged rather than aborting the whole fetch. `properties.get(...)` is used for everything inside the properties object, since its schema isn't guaranteed.

- [ ] **Step 5: Run the tests and confirm they pass**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_incois_provider.py -v
```
Expected: PASS (2 passed).

- [ ] **Step 6: Manually verify against the real INCOIS endpoint (one-off, not part of the automated suite)**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -c "
from app.providers.incois import INCOISMarineProvider
zones = INCOISMarineProvider().fetch_pfz_zones()
print(f'{len(zones)} zones fetched')
if zones:
    print(zones[0])
"
```
Expected: prints a count around 65 (real data, may vary slightly) and one real zone's fields. If this fails (network error, changed response shape), note it in your report as a concern but do not block the task on it — the mocked tests are what's graded.

- [ ] **Step 7: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (45 from before + 2 from this task = 47 passed).

- [ ] **Step 8: Commit**

```bash
git add backend/app/providers/marine.py backend/app/providers/incois.py backend/tests/test_incois_provider.py
git commit -m "feat: add MarineProvider protocol and INCOISMarineProvider"
```

---

### Task 3: Ingestion function + manual-trigger endpoint

**Files:**
- Create: `backend/app/ingestion/marine.py`
- Modify: `backend/tests/conftest.py` (add `clean_pfz_zones` fixture)
- Modify: `backend/app/main.py` (add `POST /internal/ingest/marine`)
- Test: `backend/tests/test_ingest_marine.py`

**Interfaces:**
- Consumes: `app.providers.marine:PfzZoneData`, `app.providers.marine:MarineProvider` (Task 2); `app.models:PfzZone` (Task 1); `app.db:get_engine()`.
- Produces: `app.ingestion.marine:ingest_pfz_zones(provider: MarineProvider) -> int` — calls `provider.fetch_pfz_zones()`, upserts each zone into the `pfz_zones` table keyed on `external_id` (insert if new, update if it already exists), returns the number of zones processed. Task 4 reuses the `clean_pfz_zones` fixture this task adds to `conftest.py`.

- [ ] **Step 1: Add the test fixture for cleaning up test data**

`backend/tests/conftest.py` currently starts with:
```python
import pytest
from sqlalchemy import delete

from app.config import get_settings
from app.db import get_engine
from app.models import Alert, GeocodeCache, MetarReading, WeatherReading
from app.providers.warning import AlertData
```
Change the `from app.models import Alert, GeocodeCache, MetarReading, WeatherReading` line to `from app.models import Alert, GeocodeCache, MetarReading, PfzZone, WeatherReading` (add the one new name, keep alphabetical order, don't add a second import line).

Then append this fixture to the end of the file (keep existing fixtures untouched):

```python
@pytest.fixture
def clean_pfz_zones():
    yield
    with get_engine().begin() as conn:
        conn.execute(delete(PfzZone))
```

- [ ] **Step 2: Write the failing test**

Create `backend/tests/test_ingest_marine.py`:

```python
from sqlalchemy import select

from app.db import get_engine
from app.ingestion.marine import ingest_pfz_zones
from app.models import PfzZone
from app.providers.marine import PfzZoneData


class _FakeMarineProvider:
    def __init__(self, zones: list[PfzZoneData]):
        self._zones = zones

    def fetch_pfz_zones(self) -> list[PfzZoneData]:
        return self._zones


def _sample_zone(sector_name: str = "West Coast") -> PfzZoneData:
    return PfzZoneData(
        external_id="pfzlines.1",
        category="ghrsst",
        sector_boundary=2,
        sector_name=sector_name,
        julian_day="248",
        serial_number="001",
        year=2021,
        uid=2021248001,
        length_km=45.99,
        geometry={"type": "MultiLineString", "coordinates": [[[68.4, 22.7], [68.5, 22.8]]]},
        raw_payload={"id": "pfzlines.1"},
    )


def test_ingest_pfz_zones_inserts_new_zone(clean_pfz_zones):
    count = ingest_pfz_zones(_FakeMarineProvider([_sample_zone()]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(PfzZone).where(PfzZone.external_id == "pfzlines.1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].sector_name == "West Coast"


def test_ingest_pfz_zones_upserts_existing_zone_by_external_id(clean_pfz_zones):
    ingest_pfz_zones(_FakeMarineProvider([_sample_zone(sector_name="West Coast")]))
    count = ingest_pfz_zones(_FakeMarineProvider([_sample_zone(sector_name="East Coast")]))

    assert count == 1
    with get_engine().connect() as conn:
        rows = conn.execute(
            select(PfzZone).where(PfzZone.external_id == "pfzlines.1")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].sector_name == "East Coast"
```

- [ ] **Step 3: Run the test and confirm it fails**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_ingest_marine.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.ingestion.marine'`.

- [ ] **Step 4: Write the minimal implementation**

Create `backend/app/ingestion/marine.py`:

```python
"""Scheduled ingestion for INCOIS's bounded PFZ (Potential Fishing Zone)
feature collection — same pattern as app/ingestion/alerts.py: fetch the
whole collection and upsert every row, keyed on a stable external id.
Not a per-query cache — see app/weather/service.py (cache-with-TTL) and
app/geocoding/service.py (permanent cache) for the two point-query
patterns used elsewhere in this codebase.
"""

from datetime import datetime, timezone

from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import PfzZone
from app.providers.marine import MarineProvider

_IMMUTABLE_COLUMNS = {"id", "external_id"}
_UPSERT_COLUMNS = tuple(
    col.name for col in PfzZone.__table__.columns if col.name not in _IMMUTABLE_COLUMNS
)


def ingest_pfz_zones(provider: MarineProvider) -> int:
    zones = provider.fetch_pfz_zones()
    if not zones:
        return 0

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
    return len(zones)
```

- [ ] **Step 5: Run the test and confirm it passes**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_ingest_marine.py -v
```
Expected: PASS (2 passed).

- [ ] **Step 6: Add the manual-trigger endpoint**

Modify `backend/app/main.py`. Current content is:

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
def get_metar_endpoint(
    icao: str = Query(..., min_length=4, max_length=4, pattern="^[A-Za-z]{4}$")
) -> dict:
    result = get_metar(icao)
    if result is None:
        raise HTTPException(status_code=404, detail="No METAR data for this station")
    return result
```

Change it to (add the `app.ingestion.marine` and `app.providers.incois` imports and the new route at the end — everything else is untouched):

```python
from fastapi import FastAPI, HTTPException, Query
from sqlalchemy import select

from app.aviation.service import get_metar
from app.db import check_db_connection, get_engine
from app.geocoding.service import geocode_place
from app.ingestion.alerts import ingest_alerts
from app.ingestion.marine import ingest_pfz_zones
from app.models import Alert
from app.providers.incois import INCOISMarineProvider
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
def get_metar_endpoint(
    icao: str = Query(..., min_length=4, max_length=4, pattern="^[A-Za-z]{4}$")
) -> dict:
    result = get_metar(icao)
    if result is None:
        raise HTTPException(status_code=404, detail="No METAR data for this station")
    return result


@app.post("/internal/ingest/marine")
def trigger_marine_ingestion() -> dict[str, int]:
    count = ingest_pfz_zones(INCOISMarineProvider())
    return {"ingested": count}
```

- [ ] **Step 7: Manually verify the endpoint against real INCOIS + real Postgres**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```
In a second terminal:
```bash
curl -s -X POST -w "\nHTTP_STATUS:%{http_code}\n" http://127.0.0.1:8000/internal/ingest/marine
```
Expected: `{"ingested": <a number around 65>}` and HTTP 200. Stop the server (Ctrl+C) once confirmed. If INCOIS is unreachable at verification time, note it as a concern in your report but do not block the task.

- [ ] **Step 8: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (47 from before + 2 from this task = 49 passed).

- [ ] **Step 9: Commit**

```bash
git add backend/app/ingestion/marine.py backend/app/main.py backend/tests/conftest.py backend/tests/test_ingest_marine.py
git commit -m "feat: add PFZ zone ingestion pipeline and manual-trigger endpoint"
```

---

### Task 4: Query endpoint `GET /marine/pfz-zones`

**Files:**
- Modify: `backend/app/main.py` (add `GET /marine/pfz-zones`)
- Test: `backend/tests/test_marine_endpoint.py`

**Interfaces:**
- Consumes: `app.models:PfzZone` (Task 1); `app.db:get_engine()`; `app.ingestion.marine:ingest_pfz_zones` and the `clean_pfz_zones` fixture (Task 3), used only in this task's test to seed data.
- Produces: `GET /marine/pfz-zones` → `200`, a JSON array of zone objects (one key per `PfzZone` column EXCEPT `raw_payload`, which is excluded — `geometry` IS included, since it's the substantive content, not internal bookkeeping). This route must not import or call anything from `app.providers` — it only reads Postgres.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_marine_endpoint.py`:

```python
from fastapi.testclient import TestClient

from app.ingestion.marine import ingest_pfz_zones
from app.main import app
from app.providers.marine import PfzZoneData

client = TestClient(app)


class _FakeMarineProvider:
    def __init__(self, zones: list[PfzZoneData]):
        self._zones = zones

    def fetch_pfz_zones(self) -> list[PfzZoneData]:
        return self._zones


def test_list_pfz_zones_returns_ingested_rows(clean_pfz_zones):
    zone = PfzZoneData(
        external_id="pfzlines.endpoint-test",
        category="ghrsst",
        sector_boundary=2,
        sector_name="Test Sector",
        julian_day="248",
        serial_number="099",
        year=2021,
        uid=2021248099,
        length_km=12.5,
        geometry={"type": "MultiLineString", "coordinates": [[[10.0, 10.0], [11.0, 11.0]]]},
        raw_payload={"id": "pfzlines.endpoint-test", "secret": "should not leak"},
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    response = client.get("/marine/pfz-zones")

    assert response.status_code == 200
    body = response.json()
    matching = [z for z in body if z["external_id"] == "pfzlines.endpoint-test"]
    assert len(matching) == 1
    assert matching[0]["sector_name"] == "Test Sector"
    assert matching[0]["geometry"] == zone.geometry
    assert "raw_payload" not in matching[0]
```

- [ ] **Step 2: Run the test and confirm it fails**

Run (from `backend/`, venv active, Postgres running):
```bash
./.venv/Scripts/python.exe -m pytest tests/test_marine_endpoint.py -v
```
Expected: FAIL — `404` (route doesn't exist yet).

- [ ] **Step 3: Write the minimal implementation**

Modify `backend/app/main.py`. Add `PfzZone` to the existing `from app.models import Alert` line, changing it to `from app.models import Alert, PfzZone`.

Add this route at the end of the file:

```python
@app.get("/marine/pfz-zones")
def list_pfz_zones() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    return [
        {k: v for k, v in row.items() if k != "raw_payload"}
        for row in rows
    ]
```

- [ ] **Step 4: Run the test and confirm it passes**

Run:
```bash
./.venv/Scripts/python.exe -m pytest tests/test_marine_endpoint.py -v
```
Expected: PASS.

- [ ] **Step 5: Manually verify against the running server**

Run (from `backend/`, venv active):
```bash
./.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```
In a second terminal:
```bash
curl -s -X POST http://127.0.0.1:8000/internal/ingest/marine
curl -s -w "\nHTTP_STATUS:%{http_code}\n" http://127.0.0.1:8000/marine/pfz-zones | head -c 500
```
Expected: the second call returns `200` and a JSON array (length matches whatever the ingest call reported), each item including `geometry` but never `raw_payload`. Stop the server (Ctrl+C) once confirmed.

- [ ] **Step 6: Run the full suite**

Run:
```bash
./.venv/Scripts/python.exe -m pytest -v
```
Expected: all tests pass (49 from before + 1 from this task = 50 passed).

- [ ] **Step 7: Commit**

```bash
git add backend/app/main.py backend/tests/test_marine_endpoint.py
git commit -m "feat: add GET /marine/pfz-zones query endpoint (Postgres-only, no live provider calls)"
```
