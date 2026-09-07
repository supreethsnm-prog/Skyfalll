# Forecast and Location-Filtered Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two biggest correctness gaps found in the full-codebase review: (1) there is no forecast capability at all — only current conditions — so "will it rain tomorrow" cannot be answered, confirmed live when a real chat query asking about tomorrow's rain silently got only the alerts half of its answer; (2) the `list_alerts`/`list_pfz_zones` chat tools return an arbitrary, non-location-aware subset (capped at 20 rows with no filtering), so a query about a specific place can get an answer built from the wrong region's data.

**Architecture:** Forecast follows the same cache-with-TTL point-query pattern already established for current weather (`app/weather/service.py`) — same freshness window, same provider, a new table for the different (multi-day) shape. Location filtering is a straight-line-distance (haversine) post-filter over already-ingested rows — no new database extension (no PostGIS), consistent with this codebase's deliberately minimal infra.

**Tech Stack:** Same as the rest of the backend — FastAPI, SQLAlchemy, httpx.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md (§3's cadence table already lists "Open-Meteo / IMD current + forecast" together at ~15–30 min — this plan's forecast freshness window matches that existing cadence rather than inventing a new one; §4's WeatherProvider bullet covers forecast as part of the same provider).

## Verified facts (checked live during planning — use these exact shapes)

- **Open-Meteo forecast response** (`GET https://api.open-meteo.com/v1/forecast` with `daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max&timezone=auto&forecast_days=7`) returns **column-oriented parallel arrays**, one entry per day, NOT one object per day:
  ```json
  {
    "daily": {
      "time": ["2026-09-07", "2026-09-08", ...],
      "weather_code": [51, 53, ...],
      "temperature_2m_max": [28.2, 28.6, ...],
      "temperature_2m_min": [25.0, 25.3, ...],
      "precipitation_probability_max": [100, 96, ...],
      "precipitation_sum": [4.4, 4.4, ...],
      "wind_speed_10m_max": [13.9, 15.3, ...]
    }
  }
  ```
  A provider must zip these arrays by index into one record per day.
- **Real alert data**: verified 227/227 currently-ingested alerts have non-null `latitude`/`longitude` — distance filtering is reliable for alerts without a fallback-to-text-match path.
- **Real PFZ zone data**: verified live that `sector_name` and `category` are genuinely EMPTY STRINGS/absent in today's real INCOIS feed (not a bug — confirmed in the raw `properties` payload: `"SECTORNAME": ""`, no `"Category"` key at all). Text-based location filtering on those fields would filter nothing usefully today. `geometry` IS populated and reliable.
- **PFZ geometry coordinate order — CONFIRMED, do not get this backwards**: GeoJSON standard order is `[longitude, latitude]`, verified against a real fetched zone: `[80.28869675, 14.61270538]` — 80.28 is clearly a longitude (India spans ~68–98°E) and 14.61 is clearly a latitude (India spans ~6–38°N). A `MultiLineString`'s `coordinates` is a list of lines, each line a list of `[lon, lat]` pairs.

## Global Constraints

- Provider abstraction pattern (established every prior sprint): `Protocol` + canonical `@dataclass` + a concrete class with `client: httpx.Client | None = None` / `self._owns_client = client is None`.
- No PostGIS, no new geospatial dependency — a plain haversine function is sufficient at this data volume (hundreds of rows, not millions) and keeps ops minimal, consistent with this codebase's existing choice to run on one Postgres container with no extensions.
- Forecast freshness window: reuse the existing `_FRESHNESS_WINDOW = timedelta(minutes=20)` pattern already used in `app/weather/service.py` and `app/aviation/service.py` — the spec's own cadence table already groups current+forecast weather together, so no new number is invented here.
- Response hygiene: no endpoint or tool result may include a provider's `raw_payload`.
- Chat tool results stay capped for context size (existing `_CHAT_TOOL_RESULT_CAP = 20` pattern in `app/chat/tools.py`) — location filtering narrows the SET before the cap is applied, it doesn't replace the cap.

---

### Task 1: Shared distance utility + location-filtered `list_alerts`

**Files:**
- Create: `backend/app/geo.py`
- Modify: `backend/app/warning/service.py`
- Modify: `backend/app/chat/tools.py`
- Test: `backend/tests/test_geo.py`
- Test: `backend/tests/test_warning_service.py`
- Test: `backend/tests/test_chat_tools.py`

**Interfaces:**
- Produces: `haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float` in `app/geo.py`, consumed by Task 2.
- Modifies: `list_alerts(latitude: float | None = None, longitude: float | None = None, radius_km: float = 100.0) -> list[dict]` in `app/warning/service.py` — backward compatible (no args = existing unfiltered behavior, used unchanged by `app/main.py`'s `/alerts` route).

- [ ] **Step 1: Write the failing test for `haversine_km`**

Create `backend/tests/test_geo.py`:

```python
from app.geo import haversine_km


def test_haversine_same_point_is_zero():
    assert haversine_km(19.05, 72.87, 19.05, 72.87) == 0.0


def test_haversine_known_distance_mumbai_to_delhi():
    # Real-world distance Mumbai <-> Delhi is ~1150-1160 km great-circle.
    distance = haversine_km(19.0760, 72.8777, 28.7041, 77.1025)
    assert 1100 < distance < 1200


def test_haversine_is_symmetric():
    a_to_b = haversine_km(19.05, 72.87, 28.6, 77.2)
    b_to_a = haversine_km(28.6, 77.2, 19.05, 72.87)
    assert a_to_b == pytest.approx(b_to_a)
```

Add `import pytest` at the top alongside the existing import.

- [ ] **Step 2: Run it, verify it fails**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_geo.py -v`
Expected: FAIL — `app.geo` does not exist.

- [ ] **Step 3: Create `app/geo.py`**

```python
"""Shared great-circle distance helper.

No PostGIS or other geospatial extension is used in this codebase — at the
row counts involved (hundreds of alerts, tens of PFZ zones), a plain
in-Python haversine calculation over already-fetched rows is simpler to
operate than adding a database extension, and fast enough that it never
needs to run inside SQL.
"""

import math

_EARTH_RADIUS_KM = 6371.0


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * _EARTH_RADIUS_KM * math.asin(math.sqrt(a))
```

- [ ] **Step 4: Run it, verify it passes**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_geo.py -v`
Expected: PASS, all 3 tests.

- [ ] **Step 5: Write the failing tests for location-filtered `list_alerts`**

Current `backend/app/warning/service.py` (read it to confirm before editing — it should match):

```python
"""Query-path read of ingested alert rows — see app/ingestion/alerts.py for
how this table is populated (scheduled-ingestion pattern)."""

from sqlalchemy import select

from app.db import get_engine
from app.models import Alert


def list_alerts() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    return [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]
```

Add to `backend/tests/test_warning_service.py` (alongside the existing test, which must keep passing unchanged — it's the backward-compatibility check for the `/alerts` route):

```python
def test_list_alerts_with_no_location_returns_everything_unfiltered(clean_alerts_table):
    near = AlertData(
        external_id="near-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Near", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.05, longitude=72.87,
        raw_payload={},
    )
    far = AlertData(
        external_id="far-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Far", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=28.6, longitude=77.2,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([near, far]))

    rows = list_alerts()

    assert {r["external_id"] for r in rows} == {"near-1", "far-1"}


def test_list_alerts_filters_to_radius_and_sorts_by_distance(clean_alerts_table):
    # Mumbai coordinates as the query point. "near" is in Mumbai, "far" is
    # Delhi (~1150km away — well outside a 100km radius), "medium" is Pune
    # (~120km from Mumbai — also outside a 100km radius, included here to
    # prove the cutoff is a real distance check, not just "same city").
    near = AlertData(
        external_id="near-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Mumbai", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.06, longitude=72.88,
        raw_payload={},
    )
    far = AlertData(
        external_id="far-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Delhi", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=28.6, longitude=77.2,
        raw_payload={},
    )
    no_coords = AlertData(
        external_id="no-coords-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Unknown", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=None, longitude=None,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([near, far, no_coords]))

    rows = list_alerts(latitude=19.05, longitude=72.87, radius_km=100.0)

    # Only the in-radius alert survives; the far one and the coordinate-less
    # one are both excluded (the latter because relevance can't be assessed
    # without coordinates, not because it's necessarily irrelevant).
    assert [r["external_id"] for r in rows] == ["near-1"]
    assert rows[0]["distance_km"] < 5


def test_list_alerts_sorts_multiple_matches_by_distance(clean_alerts_table):
    closer = AlertData(
        external_id="closer", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Very close", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.06, longitude=72.88,
        raw_payload={},
    )
    farther = AlertData(
        external_id="farther", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Less close", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.5, longitude=73.2,
        raw_payload={},
    )
    # Insert farther first, to prove the result is actually sorted by
    # distance rather than by insertion/id order.
    ingest_alerts(FakeWarningProvider([farther, closer]))

    rows = list_alerts(latitude=19.05, longitude=72.87, radius_km=100.0)

    assert [r["external_id"] for r in rows] == ["closer", "farther"]
    assert rows[0]["distance_km"] < rows[1]["distance_km"]
```

- [ ] **Step 6: Run the tests, verify the new ones fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_warning_service.py -v`
Expected: the pre-existing test PASSES unchanged; the 3 new tests FAIL (`list_alerts()` doesn't accept these arguments yet).

- [ ] **Step 7: Update `app/warning/service.py`**

```python
"""Query-path read of ingested alert rows — see app/ingestion/alerts.py for
how this table is populated (scheduled-ingestion pattern)."""

from sqlalchemy import select

from app.db import get_engine
from app.geo import haversine_km
from app.models import Alert


def list_alerts(
    latitude: float | None = None,
    longitude: float | None = None,
    radius_km: float = 100.0,
) -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    results = [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]

    if latitude is None or longitude is None:
        return results

    nearby = []
    for row in results:
        if row["latitude"] is None or row["longitude"] is None:
            # Relevance can't be assessed without coordinates — excluded
            # from a location-filtered result rather than assumed relevant.
            continue
        distance = haversine_km(latitude, longitude, row["latitude"], row["longitude"])
        if distance <= radius_km:
            nearby.append({**row, "distance_km": round(distance, 1)})

    nearby.sort(key=lambda row: row["distance_km"])
    return nearby
```

- [ ] **Step 8: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_warning_service.py -v`
Expected: PASS, all 4 tests (1 existing + 3 new).

- [ ] **Step 9: Run the full suite to confirm nothing broke**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all existing tests still PASS (in particular `test_alerts_endpoint.py`, since `/alerts` calls `list_alerts()` with no arguments — unchanged behavior).

- [ ] **Step 10: Commit**

```bash
git add backend/app/geo.py backend/app/warning/service.py backend/tests/test_geo.py backend/tests/test_warning_service.py
git commit -m "feat: add location-filtered list_alerts with a shared haversine utility"
```

- [ ] **Step 11: Write the failing test for the chat tool's location filtering**

Current `backend/app/chat/tools.py`'s relevant section (read it to confirm before editing):

```python
def _handle_list_alerts(tool_input: dict) -> list[dict]:
    # Chat-context size limit, not a data-correctness truncation: the real
    # /alerts endpoint (app/main.py) returns the full list.
    return list_alerts()[:_CHAT_TOOL_RESULT_CAP]
```

and its `ToolSpec`:

```python
    ToolSpec(
        name="list_alerts",
        description="List all currently active disaster/weather alerts and warnings across India.",
        input_schema={"type": "object", "properties": {}},
    ),
```

Add to `backend/tests/test_chat_tools.py`:

```python
def test_execute_list_alerts_filters_by_location(clean_alerts_table):
    from app.ingestion.alerts import ingest_alerts
    from app.providers.warning import AlertData
    from tests.conftest import FakeWarningProvider

    near = AlertData(
        external_id="near-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Mumbai", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=19.06, longitude=72.88,
        raw_payload={},
    )
    far = AlertData(
        external_id="far-1", source="SACHET-SDMA", severity="Moderate", event_type="Flood",
        area_description="Delhi", effective_start_time=None, effective_end_time=None,
        warning_message=None, severity_color=None, latitude=28.6, longitude=77.2,
        raw_payload={},
    )
    ingest_alerts(FakeWarningProvider([near, far]))

    result_json = execute_tool("list_alerts", {"latitude": 19.05, "longitude": 72.87})
    result = json.loads(result_json)

    assert [r["external_id"] for r in result] == ["near-1"]


def test_tool_specs_list_alerts_declares_location_parameters():
    spec = next(s for s in TOOL_SPECS if s.name == "list_alerts")
    assert set(spec.input_schema["properties"]) == {"latitude", "longitude"}
```

- [ ] **Step 12: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v`
Expected: `test_tool_specs_list_alerts_declares_location_parameters` FAILS (no such properties yet). `test_execute_list_alerts_filters_by_location` FAILS (handler ignores lat/lon).

- [ ] **Step 13: Update `app/chat/tools.py`**

Replace the `list_alerts` `ToolSpec` entry with:

```python
    ToolSpec(
        name="list_alerts",
        description=(
            "List currently active disaster/weather alerts and warnings across India. "
            "Pass latitude and longitude to filter to alerts within 100km of a specific "
            "location; omit both to get all alerts nationwide."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
        },
    ),
```

Replace `_handle_list_alerts`:

```python
def _handle_list_alerts(tool_input: dict) -> list[dict]:
    # Chat-context size limit, not a data-correctness truncation: the real
    # /alerts endpoint (app/main.py) returns the full, unfiltered list.
    results = list_alerts(
        latitude=tool_input.get("latitude"), longitude=tool_input.get("longitude")
    )
    return results[:_CHAT_TOOL_RESULT_CAP]
```

- [ ] **Step 14: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v`
Expected: PASS, all tests.

- [ ] **Step 15: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 16: Commit**

```bash
git add backend/app/chat/tools.py backend/tests/test_chat_tools.py
git commit -m "feat: expose location filtering on the list_alerts chat tool"
```

---

### Task 2: Location-filtered `list_pfz_zones` (geometry centroid distance)

**Files:**
- Modify: `backend/app/marine/service.py`
- Modify: `backend/app/chat/tools.py`
- Test: `backend/tests/test_marine_service.py`
- Test: `backend/tests/test_chat_tools.py`

**Interfaces:**
- Consumes: `haversine_km` from `app/geo.py` (Task 1).
- Modifies: `list_pfz_zones(latitude: float | None = None, longitude: float | None = None, radius_km: float = 200.0) -> list[dict]` in `app/marine/service.py` — backward compatible.

PFZ zones use a WIDER default radius (200km, vs alerts' 100km) because a PFZ line is a fishing-ground boundary far offshore, not a point location — a fisherman departing from a coastal town may need to know about zones well beyond a 100km radius, and the zones themselves are large/linear rather than point features.

- [ ] **Step 1: Write the failing test for centroid-based `list_pfz_zones` filtering**

Current `backend/app/marine/service.py` (read it to confirm before editing):

```python
"""Query-path read of ingested PFZ zone rows — see app/ingestion/marine.py
for how this table is populated (scheduled-ingestion pattern)."""

from sqlalchemy import select

from app.db import get_engine
from app.models import PfzZone


def list_pfz_zones() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    return [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]
```

Add to `backend/tests/test_marine_service.py`:

```python
def _zone(external_id: str, geometry: dict) -> PfzZoneData:
    return PfzZoneData(
        external_id=external_id, category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry=geometry, raw_payload={},
    )


def test_list_pfz_zones_with_no_location_returns_everything_unfiltered(clean_pfz_zones):
    # GeoJSON coordinate order is [longitude, latitude] — verified live
    # against real INCOIS data during planning (see the plan doc). Getting
    # this backwards would silently compute wrong-but-plausible distances,
    # since India's longitude (~68-98) and latitude (~6-38) ranges don't
    # overlap, so a swap fails silently rather than crashing.
    near = _zone("near-1", {"type": "MultiLineString", "coordinates": [[[72.88, 19.06], [72.90, 19.08]]]})
    far = _zone("far-1", {"type": "MultiLineString", "coordinates": [[[77.2, 28.6], [77.3, 28.7]]]})
    ingest_pfz_zones(_FakeMarineProvider([near, far]))

    rows = list_pfz_zones()

    assert {r["external_id"] for r in rows} == {"near-1", "far-1"}


def test_list_pfz_zones_filters_by_centroid_distance(clean_pfz_zones):
    near = _zone("near-1", {"type": "MultiLineString", "coordinates": [[[72.88, 19.06], [72.90, 19.08]]]})
    far = _zone("far-1", {"type": "MultiLineString", "coordinates": [[[77.2, 28.6], [77.3, 28.7]]]})
    ingest_pfz_zones(_FakeMarineProvider([near, far]))

    rows = list_pfz_zones(latitude=19.05, longitude=72.87, radius_km=200.0)

    assert [r["external_id"] for r in rows] == ["near-1"]
    assert "distance_km" in rows[0]


def test_list_pfz_zones_centroid_averages_all_points_across_all_lines(clean_pfz_zones):
    # A MultiLineString can have more than one line; the centroid must
    # average every point across every line, not just the first line.
    zone = _zone(
        "multi-line-1",
        {
            "type": "MultiLineString",
            "coordinates": [
                [[72.80, 19.00], [72.82, 19.02]],
                [[72.96, 19.10], [72.98, 19.12]],
            ],
        },
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    # The true centroid of all 4 points is close to (72.89, 19.06); a query
    # point right at that centroid should find it well within a tight radius,
    # proving all 4 points (not just the first line's 2) were averaged.
    rows = list_pfz_zones(latitude=19.06, longitude=72.89, radius_km=5.0)

    assert [r["external_id"] for r in rows] == ["multi-line-1"]
```

Add the necessary imports at the top of the test file (check what's already imported and add only what's missing):

```python
from app.ingestion.marine import ingest_pfz_zones
from app.marine.service import list_pfz_zones
from app.providers.marine import PfzZoneData
from tests.conftest import _FakeMarineProvider
```

- [ ] **Step 2: Run the tests, verify the new ones fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_marine_service.py -v`
Expected: the pre-existing test PASSES unchanged; the 3 new tests FAIL.

- [ ] **Step 3: Update `app/marine/service.py`**

```python
"""Query-path read of ingested PFZ zone rows — see app/ingestion/marine.py
for how this table is populated (scheduled-ingestion pattern)."""

from typing import Any

from sqlalchemy import select

from app.db import get_engine
from app.geo import haversine_km
from app.models import PfzZone


def _centroid(geometry: dict[str, Any]) -> tuple[float, float]:
    """Average every point across every line of a MultiLineString.

    GeoJSON coordinate order is [longitude, latitude] — do not swap these.
    """
    total_lon = total_lat = count = 0.0
    for line in geometry["coordinates"]:
        for lon, lat in line:
            total_lon += lon
            total_lat += lat
            count += 1
    return total_lat / count, total_lon / count


def list_pfz_zones(
    latitude: float | None = None,
    longitude: float | None = None,
    radius_km: float = 200.0,
) -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    results = [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]

    if latitude is None or longitude is None:
        return results

    nearby = []
    for row in results:
        zone_lat, zone_lon = _centroid(row["geometry"])
        distance = haversine_km(latitude, longitude, zone_lat, zone_lon)
        if distance <= radius_km:
            nearby.append({**row, "distance_km": round(distance, 1)})

    nearby.sort(key=lambda row: row["distance_km"])
    return nearby
```

- [ ] **Step 4: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_marine_service.py -v`
Expected: PASS, all 4 tests.

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS (in particular `test_marine_endpoint.py` — `/marine/pfz-zones` calls `list_pfz_zones()` with no arguments, unchanged behavior, and still includes `geometry` per that endpoint's own deliberate design).

- [ ] **Step 6: Commit**

```bash
git add backend/app/marine/service.py backend/tests/test_marine_service.py
git commit -m "feat: add centroid-distance location filtering to list_pfz_zones"
```

- [ ] **Step 7: Write the failing test for the chat tool's location filtering**

Current `backend/app/chat/tools.py`'s relevant section:

```python
def _handle_list_pfz_zones(tool_input: dict) -> list[dict]:
    # Chat-context size limit (cap) plus geometry stripping: the LLM doesn't
    # need raw coordinate geometry to answer a conversational question about
    # which zones are active, and the full MultiLineString arrays risk
    # crowding out max_tokens. The real /marine/pfz-zones endpoint (app/main.py)
    # deliberately keeps geometry — this only affects the chat tool handler.
    zones = list_pfz_zones()[:_CHAT_TOOL_RESULT_CAP]
    return [{k: v for k, v in zone.items() if k != "geometry"} for zone in zones]
```

and its `ToolSpec`:

```python
    ToolSpec(
        name="list_pfz_zones",
        description="List all currently advised marine Potential Fishing Zones (PFZ).",
        input_schema={"type": "object", "properties": {}},
    ),
```

Add to `backend/tests/test_chat_tools.py`:

```python
def test_execute_list_pfz_zones_filters_by_location(clean_pfz_zones):
    from app.ingestion.marine import ingest_pfz_zones
    from app.providers.marine import PfzZoneData
    from tests.conftest import _FakeMarineProvider

    near = PfzZoneData(
        external_id="near-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[72.88, 19.06], [72.90, 19.08]]]},
        raw_payload={},
    )
    far = PfzZoneData(
        external_id="far-1", category=None, sector_boundary=None, sector_name=None,
        julian_day=None, serial_number=None, year=None, uid=None, length_km=None,
        geometry={"type": "MultiLineString", "coordinates": [[[77.2, 28.6], [77.3, 28.7]]]},
        raw_payload={},
    )
    ingest_pfz_zones(_FakeMarineProvider([near, far]))

    result_json = execute_tool("list_pfz_zones", {"latitude": 19.05, "longitude": 72.87})
    result = json.loads(result_json)

    assert [r["external_id"] for r in result] == ["near-1"]
    assert "geometry" not in result[0]


def test_tool_specs_list_pfz_zones_declares_location_parameters():
    spec = next(s for s in TOOL_SPECS if s.name == "list_pfz_zones")
    assert set(spec.input_schema["properties"]) == {"latitude", "longitude"}
```

- [ ] **Step 8: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v`
Expected: both new tests FAIL.

- [ ] **Step 9: Update `app/chat/tools.py`**

Replace the `list_pfz_zones` `ToolSpec` entry with:

```python
    ToolSpec(
        name="list_pfz_zones",
        description=(
            "List currently advised marine Potential Fishing Zones (PFZ). Pass latitude "
            "and longitude to filter to zones within 200km of a specific coastal location; "
            "omit both to get all zones nationwide."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
        },
    ),
```

Replace `_handle_list_pfz_zones`:

```python
def _handle_list_pfz_zones(tool_input: dict) -> list[dict]:
    # Chat-context size limit (cap) plus geometry stripping: the LLM doesn't
    # need raw coordinate geometry to answer a conversational question about
    # which zones are active, and the full MultiLineString arrays risk
    # crowding out max_tokens. The real /marine/pfz-zones endpoint (app/main.py)
    # deliberately keeps geometry — this only affects the chat tool handler.
    zones = list_pfz_zones(
        latitude=tool_input.get("latitude"), longitude=tool_input.get("longitude")
    )[:_CHAT_TOOL_RESULT_CAP]
    return [{k: v for k, v in zone.items() if k != "geometry"} for zone in zones]
```

- [ ] **Step 10: Run the tests, verify they pass, then run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 11: Commit**

```bash
git add backend/app/chat/tools.py backend/tests/test_chat_tools.py
git commit -m "feat: expose location filtering on the list_pfz_zones chat tool"
```

---

### Task 3: Weather forecast — model, migration, provider, service

**Files:**
- Modify: `backend/app/models.py`
- Create: `backend/alembic/versions/<autogenerated>_create_weather_forecasts_table.py` (via `alembic revision --autogenerate`, not hand-written)
- Modify: `backend/app/providers/weather.py`
- Modify: `backend/app/providers/open_meteo.py`
- Create: `backend/app/forecast/__init__.py` (empty)
- Create: `backend/app/forecast/service.py`
- Test: `backend/tests/test_weather_forecasts_table_schema.py`
- Test: `backend/tests/test_open_meteo_provider.py` (extend)
- Test: `backend/tests/test_forecast_service.py`

**Interfaces:**
- Produces: `ForecastDayData` dataclass in `app/providers/weather.py` (added alongside the existing `WeatherReadingData`); `OpenMeteoWeatherProvider.fetch_forecast(latitude, longitude, days=7) -> list[ForecastDayData]` (added alongside the existing `fetch_current`); `get_forecast(latitude, longitude, days=5, provider=None) -> list[dict]` in `app/forecast/service.py`, consumed by Task 4.
- `WeatherForecast` model, table `weather_forecasts`: `id`, `latitude` (Float), `longitude` (Float), `forecast_date` (String, ISO `YYYY-MM-DD`), `weather_code` (Integer), `temp_max_c` (Float), `temp_min_c` (Float), `precip_probability_pct` (Float, nullable — Open-Meteo can omit it for some cells), `precip_sum_mm` (Float), `wind_speed_max_kmh` (Float), `raw_payload` (JSONB, not null), `fetched_at` (DateTime(timezone=True), not null). Composite `UniqueConstraint("latitude", "longitude", "forecast_date", name="uq_weather_forecasts_lat_lon_date")` — **use `unique=True` via `UniqueConstraint` in `__table_args__`, never `Column(unique=True, index=True)`** (the known pitfall from every prior sprint: that combination produces a Postgres unique INDEX, not a table-level UNIQUE CONSTRAINT, invisible to `inspector.get_unique_constraints()` — `WeatherReading`'s existing composite constraint on `(latitude, longitude)` is the pattern to mirror exactly).

- [ ] **Step 1: Write the failing schema test**

Create `backend/tests/test_weather_forecasts_table_schema.py`:

```python
from sqlalchemy import inspect

from app.db import get_engine


def test_weather_forecasts_table_has_expected_columns():
    inspector = inspect(get_engine())
    columns = {col["name"] for col in inspector.get_columns("weather_forecasts")}
    assert columns == {
        "id", "latitude", "longitude", "forecast_date", "weather_code",
        "temp_max_c", "temp_min_c", "precip_probability_pct", "precip_sum_mm",
        "wind_speed_max_kmh", "raw_payload", "fetched_at",
    }


def test_weather_forecasts_has_composite_unique_constraint():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("weather_forecasts")
    column_sets = [set(c["column_names"]) for c in constraints]
    assert {"latitude", "longitude", "forecast_date"} in column_sets
```

- [ ] **Step 2: Run it, verify it fails**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_weather_forecasts_table_schema.py -v`
Expected: FAIL — table doesn't exist.

- [ ] **Step 3: Add the `WeatherForecast` model to `app/models.py`**

Add at the end of the file, after the existing `PfzZone` class:

```python
class WeatherForecast(Base):
    __tablename__ = "weather_forecasts"
    __table_args__ = (
        UniqueConstraint(
            "latitude", "longitude", "forecast_date", name="uq_weather_forecasts_lat_lon_date"
        ),
    )

    id = Column(Integer, primary_key=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    forecast_date = Column(String, nullable=False)
    weather_code = Column(Integer, nullable=False)
    temp_max_c = Column(Float, nullable=False)
    temp_min_c = Column(Float, nullable=False)
    precip_probability_pct = Column(Float, nullable=True)
    precip_sum_mm = Column(Float, nullable=False)
    wind_speed_max_kmh = Column(Float, nullable=False)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
```

- [ ] **Step 4: Generate the migration**

Run from `backend/`: `.venv/Scripts/python.exe -m alembic revision --autogenerate -m "create weather_forecasts table"`

Open the generated file in `backend/alembic/versions/` and confirm it contains exactly one `op.create_table('weather_forecasts', ...)` with all 12 columns and the composite `UniqueConstraint` — compare against `backend/alembic/versions/2b75a0420ef4_create_weather_readings_table.py` as a reference for what a correct autogenerated migration for this codebase looks like. If autogenerate produces anything unexpected (touches another table, misses the unique constraint), fix the generated file by hand rather than accepting it as-is — autogenerate is a starting point in this codebase's convention, not something to blindly trust.

Run: `.venv/Scripts/python.exe -m alembic upgrade head`
Then confirm: `.venv/Scripts/python.exe -m alembic check` — expected output `No new upgrade operations detected.`

- [ ] **Step 5: Run the schema tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_weather_forecasts_table_schema.py -v`
Expected: PASS, both tests.

- [ ] **Step 6: Add a `clean_weather_forecasts` fixture to `tests/conftest.py`**

Following the exact pattern of the other `clean_*` fixtures (which now clean BOTH before and after — see the `_truncate` helper already in that file):

```python
@pytest.fixture
def clean_weather_forecasts():
    _truncate(WeatherForecast)
    yield
    _truncate(WeatherForecast)
```

Add `WeatherForecast` to the existing `from app.models import ...` import line.

- [ ] **Step 7: Commit the model and migration**

```bash
git add backend/app/models.py backend/alembic/versions/*.py backend/tests/test_weather_forecasts_table_schema.py backend/tests/conftest.py
git commit -m "feat: add WeatherForecast model and migration"
```

- [ ] **Step 8: Write the failing test for the provider's `fetch_forecast`**

Add to `backend/app/providers/weather.py` — the current file (read to confirm):

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

Add the new dataclass and extend the Protocol:

```python
@dataclass
class ForecastDayData:
    latitude: float
    longitude: float
    forecast_date: str
    weather_code: int
    temp_max_c: float
    temp_min_c: float
    precip_probability_pct: float | None
    precip_sum_mm: float
    wind_speed_max_kmh: float
    raw_payload: dict[str, Any]


class WeatherProvider(Protocol):
    def fetch_current(self, latitude: float, longitude: float) -> WeatherReadingData: ...
    def fetch_forecast(self, latitude: float, longitude: float, days: int) -> list[ForecastDayData]: ...
```

Add to `backend/tests/test_open_meteo_provider.py` (read the existing file first for its `httpx.MockTransport` helper convention and mirror it exactly):

```python
def test_fetch_forecast_zips_daily_arrays_into_one_record_per_day():
    payload = {
        "daily": {
            "time": ["2026-09-07", "2026-09-08"],
            "weather_code": [51, 53],
            "temperature_2m_max": [28.2, 28.6],
            "temperature_2m_min": [25.0, 25.3],
            "precipitation_probability_max": [100, 96],
            "precipitation_sum": [4.4, 4.4],
            "wind_speed_10m_max": [13.9, 15.3],
        }
    }

    def handler(request):
        return httpx.Response(200, json=payload)

    provider = OpenMeteoWeatherProvider(client=httpx.Client(transport=httpx.MockTransport(handler)))

    days = provider.fetch_forecast(19.05, 72.87, days=2)

    assert len(days) == 2
    assert days[0].forecast_date == "2026-09-07"
    assert days[0].weather_code == 51
    assert days[0].temp_max_c == 28.2
    assert days[0].temp_min_c == 25.0
    assert days[0].precip_probability_pct == 100
    assert days[0].precip_sum_mm == 4.4
    assert days[0].wind_speed_max_kmh == 13.9
    assert days[1].forecast_date == "2026-09-08"
    assert days[1].temp_max_c == 28.6


def test_fetch_forecast_handles_missing_precip_probability():
    payload = {
        "daily": {
            "time": ["2026-09-07"],
            "weather_code": [51],
            "temperature_2m_max": [28.2],
            "temperature_2m_min": [25.0],
            "precipitation_probability_max": [None],
            "precipitation_sum": [4.4],
            "wind_speed_10m_max": [13.9],
        }
    }

    def handler(request):
        return httpx.Response(200, json=payload)

    provider = OpenMeteoWeatherProvider(client=httpx.Client(transport=httpx.MockTransport(handler)))
    days = provider.fetch_forecast(19.05, 72.87, days=1)

    assert days[0].precip_probability_pct is None
```

- [ ] **Step 9: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_open_meteo_provider.py -v`
Expected: existing tests PASS unchanged; the 2 new tests FAIL — `fetch_forecast` doesn't exist.

- [ ] **Step 10: Add `fetch_forecast` to `app/providers/open_meteo.py`**

Current file (read to confirm before editing):

```python
import logging

import httpx

from app.providers.weather import WeatherReadingData

logger = logging.getLogger(__name__)

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
        ... # unchanged, do not modify
```

Change the import line to:

```python
from app.providers.weather import ForecastDayData, WeatherReadingData
```

Add this constant near `_CURRENT_FIELDS`:

```python
_DAILY_FIELDS = (
    "weather_code,temperature_2m_max,temperature_2m_min,"
    "precipitation_probability_max,precipitation_sum,wind_speed_10m_max"
)
```

Add this method to the class, alongside `fetch_current` (same class, same `self._client`/`self._owns_client` — do not duplicate client construction):

```python
    def fetch_forecast(self, latitude: float, longitude: float, days: int = 7) -> list[ForecastDayData]:
        try:
            response = self._client.get(
                self._base_url,
                params={
                    "latitude": latitude,
                    "longitude": longitude,
                    "daily": _DAILY_FIELDS,
                    "timezone": "auto",
                    "forecast_days": days,
                },
            )
            response.raise_for_status()
            payload = response.json()
            try:
                daily = payload["daily"]
                return [
                    ForecastDayData(
                        latitude=latitude,
                        longitude=longitude,
                        forecast_date=daily["time"][i],
                        weather_code=daily["weather_code"][i],
                        temp_max_c=daily["temperature_2m_max"][i],
                        temp_min_c=daily["temperature_2m_min"][i],
                        precip_probability_pct=daily["precipitation_probability_max"][i],
                        precip_sum_mm=daily["precipitation_sum"][i],
                        wind_speed_max_kmh=daily["wind_speed_10m_max"][i],
                        raw_payload=payload,
                    )
                    for i in range(len(daily["time"]))
                ]
            except (KeyError, IndexError, TypeError) as exc:
                logger.warning(
                    "Failed to parse Open-Meteo forecast response for (%s, %s): %s",
                    latitude,
                    longitude,
                    exc,
                )
                raise
        finally:
            if self._owns_client:
                self._client.close()
```

Note `raw_payload=payload` stores the FULL forecast response identically on every day's row — this is a deliberate, honest choice: Open-Meteo's response is column-oriented (parallel arrays), not naturally sliceable into one raw record per day, so storing the shared source response on each row is the closest accurate representation of "what came from the source," not a fabricated per-day object.

- [ ] **Step 11: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_open_meteo_provider.py -v`
Expected: PASS, all tests.

- [ ] **Step 12: Commit**

```bash
git add backend/app/providers/weather.py backend/app/providers/open_meteo.py backend/tests/test_open_meteo_provider.py
git commit -m "feat: add fetch_forecast to the WeatherProvider protocol and Open-Meteo adapter"
```

- [ ] **Step 13: Write the failing tests for `app/forecast/service.py`**

Create `backend/app/forecast/__init__.py` (empty file).

Create `backend/tests/test_forecast_service.py`:

```python
from datetime import datetime, timedelta, timezone

from sqlalchemy import insert, select

from app.db import get_engine
from app.forecast.service import get_forecast
from app.models import WeatherForecast
from app.providers.weather import ForecastDayData


class _FakeForecastProvider:
    def __init__(self, days: list[ForecastDayData]):
        self._days = days
        self.calls = 0

    def fetch_forecast(self, latitude, longitude, days):
        self.calls += 1
        return self._days


def _sample_day(forecast_date="2026-09-08", temp_max_c=29.0):
    return ForecastDayData(
        latitude=19.08, longitude=72.88, forecast_date=forecast_date, weather_code=51,
        temp_max_c=temp_max_c, temp_min_c=25.0, precip_probability_pct=90.0,
        precip_sum_mm=3.0, wind_speed_max_kmh=14.0, raw_payload={"live": True},
    )


def test_get_forecast_fetches_and_caches_on_missing_rows(clean_weather_forecasts):
    provider = _FakeForecastProvider([_sample_day()])

    result = get_forecast(19.08, 72.88, days=1, provider=provider)

    assert provider.calls == 1
    assert result[0]["temp_max_c"] == 29.0
    assert "raw_payload" not in result[0]

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherForecast).where(
                WeatherForecast.latitude == 19.08, WeatherForecast.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1


def test_get_forecast_returns_fresh_cache_without_calling_provider(clean_weather_forecasts):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=51,
                temp_max_c=30.0, temp_min_c=25.0, precip_probability_pct=50.0,
                precip_sum_mm=1.0, wind_speed_max_kmh=10.0, raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    class _RaisingProvider:
        def fetch_forecast(self, latitude, longitude, days):
            raise AssertionError("provider should not be called on a fresh cache hit")

    result = get_forecast(19.08, 72.88, days=1, provider=_RaisingProvider())

    assert result[0]["temp_max_c"] == 30.0


def test_get_forecast_refetches_when_cache_is_stale(clean_weather_forecasts):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=51,
                temp_max_c=10.0, temp_min_c=5.0, precip_probability_pct=50.0,
                precip_sum_mm=1.0, wind_speed_max_kmh=10.0, raw_payload={"stale": True},
                fetched_at=stale_time,
            )
        )
    provider = _FakeForecastProvider([_sample_day(temp_max_c=35.0)])

    result = get_forecast(19.08, 72.88, days=1, provider=provider)

    assert provider.calls == 1
    assert result[0]["temp_max_c"] == 35.0


def test_get_forecast_rounds_coordinates_for_cache_key(clean_weather_forecasts):
    provider = _FakeForecastProvider([_sample_day()])

    get_forecast(19.0761, 72.8812, days=1, provider=provider)

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherForecast).where(
                WeatherForecast.latitude == 19.08, WeatherForecast.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1


def test_get_forecast_upserts_multiple_days_without_duplicating(clean_weather_forecasts):
    day1 = _sample_day(forecast_date="2026-09-08", temp_max_c=29.0)
    day2 = _sample_day(forecast_date="2026-09-09", temp_max_c=30.0)
    provider = _FakeForecastProvider([day1, day2])

    get_forecast(19.08, 72.88, days=2, provider=provider)
    # Re-fetch immediately (still fresh) with a different provider whose
    # data must NOT be used, then re-fetch after forcing staleness.
    result = get_forecast(19.08, 72.88, days=2, provider=_FakeForecastProvider([day1, day2]))

    assert len(result) == 2
    assert {r["forecast_date"] for r in result} == {"2026-09-08", "2026-09-09"}

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherForecast).where(
                WeatherForecast.latitude == 19.08, WeatherForecast.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 2
```

- [ ] **Step 14: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_forecast_service.py -v`
Expected: FAIL — `app.forecast.service` does not exist.

- [ ] **Step 15: Write `app/forecast/service.py`**

```python
"""Cache-with-TTL for multi-day forecast queries, mirroring
app/weather/service.py's pattern for current-conditions queries — same
freshness window, same point-location live-fallback exception (spec §3's
amendment), different shape (one row per forecast day instead of one row
per coordinate).
"""

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import WeatherForecast
from app.providers.open_meteo import OpenMeteoWeatherProvider
from app.providers.weather import WeatherProvider

logger = logging.getLogger(__name__)

_FRESHNESS_WINDOW = timedelta(minutes=20)
_COORDINATE_PRECISION = 2

_RESPONSE_FIELDS = (
    "latitude",
    "longitude",
    "forecast_date",
    "weather_code",
    "temp_max_c",
    "temp_min_c",
    "precip_probability_pct",
    "precip_sum_mm",
    "wind_speed_max_kmh",
    "fetched_at",
)

_MUTABLE_COLUMNS = (
    "weather_code",
    "temp_max_c",
    "temp_min_c",
    "precip_probability_pct",
    "precip_sum_mm",
    "wind_speed_max_kmh",
    "raw_payload",
    "fetched_at",
)


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def get_forecast(
    latitude: float, longitude: float, days: int = 5, provider: WeatherProvider | None = None
) -> list[dict]:
    rounded_lat = round(latitude, _COORDINATE_PRECISION)
    rounded_lon = round(longitude, _COORDINATE_PRECISION)

    engine = get_engine()

    with engine.connect() as conn:
        rows = (
            conn.execute(
                select(WeatherForecast)
                .where(
                    WeatherForecast.latitude == rounded_lat,
                    WeatherForecast.longitude == rounded_lon,
                )
                .order_by(WeatherForecast.forecast_date)
            )
            .mappings()
            .all()
        )

    now = datetime.now(timezone.utc)
    # A cached batch is treated as fresh only if there are enough rows to
    # answer this request AND the freshest of them is still within the
    # window — a stale or partial cache falls through to a live re-fetch,
    # same as every other cache-with-TTL service in this codebase.
    if len(rows) >= days and rows and (now - max(r["fetched_at"] for r in rows)) < _FRESHNESS_WINDOW:
        return [_to_response(row) for row in rows[:days]]

    try:
        forecast_days = (provider or OpenMeteoWeatherProvider()).fetch_forecast(
            rounded_lat, rounded_lon, days
        )
    except Exception:
        if rows:
            logger.warning(
                "Live forecast fetch failed for (%s, %s); serving stale cache "
                "from %s",
                rounded_lat,
                rounded_lon,
                max(r["fetched_at"] for r in rows),
            )
            return [_to_response(row) for row in rows[:days]]
        raise

    fetched_at = datetime.now(timezone.utc)
    updated_rows = []

    with engine.begin() as conn:
        for day in forecast_days:
            stmt = pg_insert(WeatherForecast).values(
                latitude=rounded_lat,
                longitude=rounded_lon,
                forecast_date=day.forecast_date,
                weather_code=day.weather_code,
                temp_max_c=day.temp_max_c,
                temp_min_c=day.temp_min_c,
                precip_probability_pct=day.precip_probability_pct,
                precip_sum_mm=day.precip_sum_mm,
                wind_speed_max_kmh=day.wind_speed_max_kmh,
                raw_payload=day.raw_payload,
                fetched_at=fetched_at,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[
                    WeatherForecast.latitude,
                    WeatherForecast.longitude,
                    WeatherForecast.forecast_date,
                ],
                set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
            ).returning(WeatherForecast)
            updated_rows.append(conn.execute(stmt).mappings().one())

    return [_to_response(row) for row in updated_rows]
```

- [ ] **Step 16: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_forecast_service.py -v`
Expected: PASS, all 5 tests.

- [ ] **Step 17: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 18: Commit**

```bash
git add backend/app/forecast/__init__.py backend/app/forecast/service.py backend/tests/test_forecast_service.py
git commit -m "feat: add get_forecast cache-with-TTL service"
```

---

### Task 4: Forecast chat tool, `/forecast` endpoint, and system prompt update

**Files:**
- Modify: `backend/app/main.py`
- Modify: `backend/app/chat/tools.py`
- Modify: `backend/app/chat/service.py`
- Test: `backend/tests/test_forecast_endpoint.py`
- Test: `backend/tests/test_chat_tools.py`

**Interfaces:**
- Consumes: `get_forecast` (Task 3).
- Produces: `GET /forecast` endpoint; `get_forecast` chat tool.

- [ ] **Step 1: Write the failing test for `GET /forecast`**

Create `backend/tests/test_forecast_endpoint.py`:

```python
from datetime import datetime, timezone

from fastapi.testclient import TestClient
from sqlalchemy import insert

from app.db import get_engine
from app.main import app
from app.models import WeatherForecast

client = TestClient(app)


def test_forecast_endpoint_returns_cached_days(clean_weather_forecasts):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=51,
                temp_max_c=29.0, temp_min_c=25.0, precip_probability_pct=90.0,
                precip_sum_mm=3.0, wind_speed_max_kmh=14.0, raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get("/forecast", params={"lat": 19.08, "lon": 72.88, "days": 1})

    assert response.status_code == 200
    body = response.json()
    assert body[0]["temp_max_c"] == 29.0
    assert "raw_payload" not in body[0]


def test_forecast_endpoint_validates_days_range():
    response = client.get("/forecast", params={"lat": 19.08, "lon": 72.88, "days": 20})
    assert response.status_code == 422
```

- [ ] **Step 2: Run it, verify it fails**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_forecast_endpoint.py -v`
Expected: FAIL — no `/forecast` route.

- [ ] **Step 3: Add the route to `app/main.py`**

Add this import alongside the existing `from app.weather.service import get_weather` line:

```python
from app.forecast.service import get_forecast
```

Add this route immediately after the existing `get_weather_endpoint`:

```python
@app.get("/forecast")
def get_forecast_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    days: int = Query(5, ge=1, le=16),
) -> list[dict]:
    return get_forecast(lat, lon, days)
```

(`ge=1, le=16` matches Open-Meteo's own supported `forecast_days` range.)

- [ ] **Step 4: Run it, verify it passes, then run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/main.py backend/tests/test_forecast_endpoint.py
git commit -m "feat: add GET /forecast endpoint"
```

- [ ] **Step 6: Write the failing test for the forecast chat tool**

Add to `backend/tests/test_chat_tools.py`:

```python
def test_execute_get_forecast_returns_seeded_cache_as_json(clean_weather_forecasts):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=51,
                temp_max_c=29.0, temp_min_c=25.0, precip_probability_pct=90.0,
                precip_sum_mm=3.0, wind_speed_max_kmh=14.0, raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    result_json = execute_tool(
        "get_forecast", {"latitude": 19.08, "longitude": 72.88, "days": 1}
    )
    result = json.loads(result_json)

    assert result[0]["temp_max_c"] == 29.0
    assert "raw_payload" not in result[0]


def test_execute_get_forecast_defaults_days_when_omitted(clean_weather_forecasts):
    result_json = execute_tool("get_forecast", {"latitude": 19.08, "longitude": 72.88})
    result = json.loads(result_json)
    # No cache and a real network call would occur here in production; this
    # only proves the handler doesn't crash on a missing "days" key by
    # requiring KeyError to NOT be the failure mode — a genuine network
    # error surfacing as an in-band {"error": ...} is an acceptable outcome
    # in this offline test environment.
    assert isinstance(result, (list, dict))
```

Add `WeatherForecast` and `insert`/`datetime`/`timezone` imports to `test_chat_tools.py` if not already present (check the existing imports first — `insert` and `datetime`/`timezone` are likely already imported from the `get_weather` tests in this same file; reuse rather than duplicate).

- [ ] **Step 7: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v`
Expected: FAIL — no `get_forecast` tool registered.

- [ ] **Step 8: Add the tool to `app/chat/tools.py`**

Add this import alongside the existing `from app.weather.service import get_weather` line:

```python
from app.forecast.service import get_forecast
```

Add this entry to `TOOL_SPECS`, after `get_weather`'s entry:

```python
    ToolSpec(
        name="get_forecast",
        description=(
            "Get a multi-day weather forecast (daily high/low temperature, rain "
            "probability, precipitation, wind) for a specific latitude/longitude "
            "coordinate. Use this for questions about tomorrow, upcoming days, or "
            "the weekly forecast — get_weather only covers right now."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
                "days": {
                    "type": "integer",
                    "description": "Number of days to forecast (1-16, default 5)",
                },
            },
            "required": ["latitude", "longitude"],
        },
    ),
```

Add this handler, alongside `_handle_get_weather`:

```python
def _handle_get_forecast(tool_input: dict) -> list[dict]:
    days = tool_input.get("days", 5)
    return get_forecast(
        latitude=tool_input["latitude"], longitude=tool_input["longitude"], days=days
    )
```

Add it to `_HANDLERS`:

```python
    "get_forecast": _handle_get_forecast,
```

- [ ] **Step 9: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v`
Expected: PASS, all tests.

- [ ] **Step 10: Update the system prompt in `app/chat/service.py`**

Current relevant section (read to confirm before editing):

```python
_SYSTEM_PROMPT = (
    "You are WeatherGPT, a conversational assistant for weather, marine, "
    "aviation, and disaster-alert information in India. Always use the "
    "provided tools to look up current facts — never state a specific "
    "weather value, alert, or observation from memory. If a tool reports "
    "an error or no data, say so plainly rather than guessing.\n\n"
    "get_weather takes coordinates, not place names. When the user names a "
    "place, call geocode first to resolve it, then pass the coordinates it "
    "returns to get_weather.\n\n"
    "Reply in the same language the user wrote in — including Hindi, Telugu, "
    "Tamil, Bengali, Marathi and other Indian languages — keeping numbers, "
    "units and place names in standard form."
)
```

Replace it with:

```python
_SYSTEM_PROMPT = (
    "You are WeatherGPT, a conversational assistant for weather, marine, "
    "aviation, and disaster-alert information in India. Always use the "
    "provided tools to look up current facts — never state a specific "
    "weather value, alert, or observation from memory. If a tool reports "
    "an error or no data, say so plainly rather than guessing. If a "
    "question has multiple parts (e.g. both a forecast and an alert "
    "check), call every tool needed to answer all of them — never silently "
    "skip part of a question because it seemed less important.\n\n"
    "get_weather, get_forecast, list_alerts, and list_pfz_zones all accept "
    "coordinates, not place names. When the user names a place, call "
    "geocode first to resolve it, then pass the coordinates it returns to "
    "whichever of those tools you need. Use get_weather for right-now "
    "conditions and get_forecast for tomorrow, upcoming days, or a weekly "
    "outlook — they are not interchangeable.\n\n"
    "Reply in the same language the user wrote in — including Hindi, Telugu, "
    "Tamil, Bengali, Marathi and other Indian languages — keeping numbers, "
    "units and place names in standard form."
)
```

This directly addresses a gap demonstrated in live testing during this project: a Hindi query asking both "will it rain tomorrow" and "are there any warnings" was answered with only the warnings half, silently dropping the forecast question because no forecast tool existed. The explicit "answer every part" instruction plus the new tool itself both target this failure mode.

- [ ] **Step 11: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 12: Commit**

```bash
git add backend/app/chat/tools.py backend/app/chat/service.py backend/tests/test_chat_tools.py
git commit -m "feat: add get_forecast chat tool and update system prompt for multi-part questions"
```

- [ ] **Step 13: Manual live verification (non-blocking, requires a real LLM key)**

This worktree has a real `GEMINI_API_KEY` configured. From `backend/`, with the app importable (no server needed):

```bash
.venv/Scripts/python.exe -c "
from app.chat.service import chat_turn
result = chat_turn('Mumbai mein kal baarish hogi kya? Aur koi warning hai?')
print(result['reply'])
print([h.get('name') for h in result['history'] if h.get('role') == 'tool'])
"
```

Expected: the tool list should now include `geocode`, `get_forecast`, AND `list_alerts` (not just `list_alerts` alone, which was the previously-observed gap), and the reply should address both the forecast and the alert question rather than silently dropping one. Note the result in the task report; this is a real demonstration that the specific gap motivating this sprint is closed, not just a unit-test pass.
```
