# ERA5 Historical Weather Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `HistoricalWeatherProvider` the V1 spec requires (§4: "ERA5 via Copernicus Climate Data Store, current client (`ecmwf-datastores-client`), self-serve account + per-dataset license acceptance") — a one-time seed of real ERA5 reanalysis data for a fixed set of Indian cities/dates, queried thereafter with zero live CDS calls at request time.

**Architecture:** ERA5 introduces a SIXTH query-path pattern, distinct from every other source in this codebase — **one-time seed, never live-fetched again**. Every other scheduled/cached source in this app assumes request latency measured in milliseconds-to-seconds; CDS's real queue-plus-compute latency is **25 seconds to 2 minutes per request** (confirmed live, repeatedly, this session — see "Verified facts"), categorically incompatible with a request/response HTTP cycle or even a reasonable scheduled-ingestion interval. The spec's own cadence table already calls ERA5 "one-off/periodic batch, not polled" — this plan takes that literally: a standalone script (`backend/scripts/seed_era5_history.py`, run manually, once, by a human — NOT wired into `IngestionScheduler`, NOT run by any test) populates a small, fixed set of (city, date) combinations into Postgres. `app/history/service.py`'s query function only ever reads that table.

**Tech Stack:** `ecmwf-datastores-client==0.5.3` (the exact client the spec names) + `h5netcdf==1.8.1` + `h5py==3.16.0` (NetCDF4/HDF5 backend for `xarray` — ERA5's NetCDF responses are HDF5-based, not the plain NetCDF3 format `scipy` can read; confirmed live this session) + `xarray` (already a dependency since the GFS sprint).

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md

## Verified facts (live, this session — not assumed)

All verified by actually registering a real CDS account, accepting the real dataset's Terms of Use, and making multiple real requests against the live API:

- **Auth**: `ecmwf-datastores-client` reads `ECMWF_DATASTORES_URL` and `ECMWF_DATASTORES_KEY` environment variables directly (confirmed from the library's own README) — no `~/.ecmwfdatastoresrc` dotfile needed, fitting this codebase's `.env`-based config pattern. The real key is already in `backend/.env` as `CDS_API_KEY`; this plan wires it into the two env vars the client actually expects at construction time (see Task 2).
- **Terms of Use acceptance is a real, separate, manual, one-time step** — done on the dataset's own CDS webpage, not via the API. Already completed for this project's account against `reanalysis-era5-single-levels` ("ERA5 hourly data on single levels from 1940 to present") — confirmed by a real successful request against exactly that dataset.
- **Real observed latency across 5 live requests this session**: 25 seconds to ~2 minutes, dominated entirely by CDS's shared queue (`accepted`→`running` wait), not compute or download (downloads of these small files are sub-second to a few seconds). **This must never be called synchronously inside an HTTP request handler or a short-interval scheduled job** — it is only usable from a script willing to block for minutes.
- **The response format is genuinely inconsistent by request shape, confirmed by direct observation, not assumed:** a request bundling both "instantaneous" variables (temperature, wind, pressure) and an "accumulated" variable (precipitation) in one call returns a **ZIP archive** containing TWO separate NetCDF files — `data_stream-oper_stepType-instant.nc` and `data_stream-oper_stepType-accum.nc` — not one combined file. (This mirrors the GFS sprint's own instantaneous-vs-accumulated split, for the same underlying reason: ECMWF's accumulated fields have their own `stepType`.) A single-variable, single-steptype request may return a plain `.nc` file instead. **The parsing code must check `zipfile.is_zipfile(path)` and handle both cases** — do not assume either format.
- **Real NetCDF structure** (from an actual downloaded, extracted, and inspected zip — this exact file is committed as a test fixture, see Task 2): dimensions `valid_time` (1), `latitude` (4), `longitude` (4) for a small ~1°×1° request box. **Latitude descends** (e.g. `19.5, 19.25, 19.0, 18.75`), **longitude is signed -180/180** (e.g. `72.5, 72.75, 73.0, 73.25` for a Mumbai-area box) — this is DIFFERENT from GFS's 0-360°E convention (not that it matters for India's positive-longitude coordinates, but the two providers must not share coordinate-handling code that assumes GFS's convention). Data variables use GRIB/CF short names, confirmed live: `t2m`, `d2m`, `u10`, `v10`, `msl` (in the "instant" file), `tp` (in the "accum" file).
- **Confirmed real API variable-name strings** (read directly from the live API's own JSON schema, not guessed): `2m_temperature`, `2m_dewpoint_temperature`, `total_precipitation`, `10m_u_component_of_wind`, `10m_v_component_of_wind`, `mean_sea_level_pressure`. The request's canonical field name for output format is `data_format` (not `format`, though `format` is tolerated as a legacy alias) — use `data_format`.
- **Real confirmed units and conversions**, verified against real downloaded values at Mumbai (19.08°N, 72.88°E) on 2023-07-15 12:00 UTC: `t2m`/`d2m` in Kelvin (real value 300.45 K → 27.30°C; convert with `- 273.15`); `tp` in **meters** of water equivalent (real value 0.00073 m → 0.73mm; convert with `* 1000`); `msl` in Pascals (real value 100651.6 Pa → 1006.52 hPa; convert with `/ 100`); `u10`/`v10` already in m/s (no conversion — combine into speed via `hypot(u,v) * 3.6` for km/h and direction via `atan2(-u,-v) % 360` for the meteorological "from" convention, the exact same formula already used and verified in this codebase's GFS provider). All five real converted values above are physically sane for a Mumbai monsoon noon (27.3°C, 25.4°C dewpoint indicating high humidity, ~16 km/h wind from the southwest, 1006.5 hPa, light 0.73mm rain).
- **CDS request parameter `area`** uses `[North, West, South, East]` (confirmed: a request for `[19.6, 72.4, 18.6, 73.4]` returned exactly the Mumbai-area box expected).
- **No hard published rate limit** — CDS queues excess load rather than rejecting it ("limits are changed from time to time according to the current workload of the system," per ECMWF's own documentation). A real field-count cap exists (~60,000-120,000 fields/request) but is irrelevant at this plan's scale (1 field per variable per request). Large-area/high-resolution requests are explicitly deprioritized — this plan's small ~1° boxes avoid that entirely.

## Global Constraints

- No LLM call, no raw provider call from any query-path service — `app/history/service.py` reads only from Postgres, exactly like every other query-path service in this codebase.
- `ecmwf-datastores-client==0.5.3`, `h5netcdf==1.8.1`, `h5py==3.16.0` pinned EXACTLY in `requirements.txt`/`requirements.lock` (all three confirmed to install cleanly on this Windows/Python 3.13 environment this session).
- The seed script (`backend/scripts/seed_era5_history.py`) is explicitly OUTSIDE the FastAPI app and its scheduler — never imported by `app/main.py`, never registered as an `IngestionScheduler` job, never run by the automated test suite. It is a manual, human-triggered, one-time operation, run once during this sprint's Task 3 and optionally re-run later if more (city, date) coverage is wanted.
- Provider-layer tests (Task 2) never make a real network call — the committed fixture at `backend/tests/fixtures/era5_mumbai_sample.zip` (a real, live-captured CDS response, ~88KB) is used for all offline parsing tests. Task 3's actual full seed run against the live API is the plan's one deliberate, necessary live execution — not a "manual verification step" in the lighter sense used by prior sprints, but the actual population of real production data, expected to take roughly 20-40 minutes of wall-clock time for the full (city, date) matrix below.
- No `raw_payload` column on the new table — same deliberate deviation from this codebase's usual per-provider convention as GFS's `GfsForecastPoint` (fully-typed scalar columns with well-documented units; no unpredictable upstream schema to guard against).
- The seed script's (city, date) matrix is fixed and small (see Task 3) — this plan does not build a general-purpose "any city, any date" live lookup; that would require a genuinely different, asynchronous job-submission architecture (CDS's own `client.submit()`/`Remote`/`client.get_remote(request_id)` primitives exist and would support it, confirmed this session, but building that is explicitly out of scope for V1 per the spec's own "batch, not polled" framing).

---

## Task 1: `HistoricalWeatherReading` model + Alembic migration

**Files:**
- Modify: `backend/app/models.py`
- Create: Alembic migration (run `alembic revision --autogenerate -m "add historical_weather_readings table"` after adding the model, from `backend/`)
- Test: `backend/tests/test_historical_weather_readings_table_schema.py`

**Interfaces:**
- Produces: `HistoricalWeatherReading` ORM model, table `historical_weather_readings`, unique constraint on `(location_name, observation_date)` — Task 3's seed script upserts against this constraint, Task 4's query service selects by it.

- [ ] **Step 1: Add the model to `backend/app/models.py`**

```python
class HistoricalWeatherReading(Base):
    __tablename__ = "historical_weather_readings"
    __table_args__ = (
        UniqueConstraint(
            "location_name", "observation_date", name="uq_historical_weather_location_date"
        ),
    )

    id = Column(Integer, primary_key=True)
    location_name = Column(String, nullable=False, index=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    observation_date = Column(String, nullable=False)
    temp_2m_c = Column(Float, nullable=True)
    dewpoint_2m_c = Column(Float, nullable=True)
    precip_mm = Column(Float, nullable=True)
    wind_speed_10m_kmh = Column(Float, nullable=True)
    wind_direction_10m_deg = Column(Float, nullable=True)
    mslp_hpa = Column(Float, nullable=True)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
```

All six weather-field columns are deliberately `nullable=True` — if ERA5 ever omits one field for a given request (unlikely, but consistent with this codebase's general "partial is better than broken" posture, see `GfsForecastPoint`'s identical choice), the row should still be written with whatever fields succeeded rather than being dropped entirely.

- [ ] **Step 2: Write the failing schema test**

Create `backend/tests/test_historical_weather_readings_table_schema.py`:

```python
from sqlalchemy import inspect

from app.db import get_engine


def test_historical_weather_readings_table_has_expected_columns():
    inspector = inspect(get_engine())
    columns = {col["name"] for col in inspector.get_columns("historical_weather_readings")}
    assert columns == {
        "id", "location_name", "latitude", "longitude", "observation_date",
        "temp_2m_c", "dewpoint_2m_c", "precip_mm", "wind_speed_10m_kmh",
        "wind_direction_10m_deg", "mslp_hpa", "fetched_at",
    }


def test_historical_weather_readings_has_unique_constraint_on_location_and_date():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("historical_weather_readings")
    names = {frozenset(c["column_names"]) for c in constraints}
    assert frozenset({"location_name", "observation_date"}) in names
```

- [ ] **Step 3: Run test, verify it fails**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_historical_weather_readings_table_schema.py -v`
Expected: FAIL — table doesn't exist yet.

- [ ] **Step 4: Generate and apply the Alembic migration**

```bash
cd backend
.venv/Scripts/python.exe -m alembic revision --autogenerate -m "add historical_weather_readings table"
.venv/Scripts/python.exe -m alembic upgrade head
```

Read the generated migration file and confirm it matches the model exactly (standard practice for every migration in this project — verify, don't assume autogenerate got it right).

- [ ] **Step 5: Run test, verify it passes**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_historical_weather_readings_table_schema.py -v`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS (343 pre-existing + 2 new).

- [ ] **Step 7: Commit**

```bash
git add backend/app/models.py backend/alembic/versions/ backend/tests/test_historical_weather_readings_table_schema.py
git commit -m "feat: add historical_weather_readings table"
```

---

## Task 2: `HistoricalWeatherProvider` protocol + `CdsEra5Provider`

**Files:**
- Create: `backend/app/providers/historical.py` (protocol + dataclass)
- Create: `backend/app/providers/era5.py` (`CdsEra5Provider`)
- Create: `backend/tests/fixtures/era5_mumbai_sample.zip` (already captured this session — copy from the path noted in Step 1; a real, live CDS response, ~88KB)
- Test: `backend/tests/test_era5_provider.py`
- Modify: `backend/requirements.txt`, `backend/requirements.lock`

**Interfaces:**
- Produces: `Era5ReadingData` dataclass (fields matching Task 1's model columns minus `id`/`fetched_at`). `CdsEra5Provider.fetch_reading(location_name: str, latitude: float, longitude: float, observation_date: str) -> Era5ReadingData | None` — Task 3's seed script calls this once per (city, date) pair. `observation_date` is a `"YYYY-MM-DD"` string.

This is the highest-risk task in this plan — the zip-vs-plain-file response handling and the exact unit conversions need to be genuinely correct, not just plausible. Take the fixture-based tests seriously.

- [ ] **Step 1: Copy the pre-captured test fixture into the repo**

A real, live CDS response for Mumbai (19.08°N, 72.88°E), 2023-07-15 12:00 UTC, requesting all six variables this provider needs, already exists at:
`C:\Users\ACER\AppData\Local\Temp\era5_fixture_source.nc` — **note: despite the `.nc` extension on the original download, this file is actually a ZIP archive** (confirmed: magic bytes `PK\x03\x04`, contains `data_stream-oper_stepType-instant.nc` and `data_stream-oper_stepType-accum.nc`). Copy it into the repo with a correctly-named extension:

```bash
cp "C:/Users/ACER/AppData/Local/Temp/era5_fixture_source.nc" backend/tests/fixtures/era5_mumbai_sample.zip
```

If that temp file no longer exists on this machine (e.g. cleaned up), recreate it with a real live request (the account's credentials and terms acceptance are already confirmed working):
```python
import os
os.environ['ECMWF_DATASTORES_URL'] = 'https://cds.climate.copernicus.eu/api'
os.environ['ECMWF_DATASTORES_KEY'] = '<read CDS_API_KEY from backend/.env>'
import ecmwf.datastores as eds
client = eds.Client()
client.retrieve(
    'reanalysis-era5-single-levels',
    {
        'product_type': 'reanalysis',
        'variable': ['2m_temperature', '2m_dewpoint_temperature', 'total_precipitation',
                     '10m_u_component_of_wind', '10m_v_component_of_wind', 'mean_sea_level_pressure'],
        'year': '2023', 'month': '07', 'day': '15', 'time': '12:00',
        'area': [19.6, 72.4, 18.6, 73.4],
        'data_format': 'netcdf',
    },
    target='backend/tests/fixtures/era5_mumbai_sample.zip',
)
```

- [ ] **Step 2: Pin the new dependencies**

Add to `backend/requirements.txt`:
```
ecmwf-datastores-client==0.5.3
h5netcdf==1.8.1
h5py==3.16.0
```

Add the same three exact versions to `backend/requirements.lock` (alphabetically merged with the existing entries — check what transitive dependencies `pip install` pulls in and add those too, following the exact pattern used when GFS's `cfgrib`/`eccodes`/`xarray` were added to this same file).

Run `.venv/Scripts/python.exe -m pip install -r requirements.lock` and confirm all three import cleanly: `python -c "import ecmwf.datastores, h5netcdf, h5py"`.

- [ ] **Step 3: Write the protocol and dataclass in `backend/app/providers/historical.py`**

```python
"""HistoricalWeatherProvider: ERA5 reanalysis data (spec section 4's
"Historical/climate" requirement). Unlike every other provider in this
codebase, this is never called at request time or on any scheduled
interval — see app/providers/era5.py's module docstring and
backend/scripts/seed_era5_history.py for why: a single CDS request takes
25 seconds to 2 minutes (confirmed live), categorically incompatible with
an HTTP request cycle or a short polling interval.
"""

from dataclasses import dataclass
from typing import Protocol


@dataclass
class Era5ReadingData:
    location_name: str
    latitude: float
    longitude: float
    observation_date: str
    temp_2m_c: float | None
    dewpoint_2m_c: float | None
    precip_mm: float | None
    wind_speed_10m_kmh: float | None
    wind_direction_10m_deg: float | None
    mslp_hpa: float | None


class HistoricalWeatherProvider(Protocol):
    def fetch_reading(
        self, location_name: str, latitude: float, longitude: float, observation_date: str
    ) -> Era5ReadingData | None: ...
```

- [ ] **Step 4: Write the failing fixture-based parsing test**

Create `backend/tests/test_era5_provider.py`:

```python
from app.providers.era5 import CdsEra5Provider


def test_parses_the_real_committed_fixture_into_correct_converted_values():
    provider = CdsEra5Provider(client=None)  # no real client needed for this test — see Step 6
    reading = provider._parse_response(
        "tests/fixtures/era5_mumbai_sample.zip",
        location_name="Mumbai",
        latitude=19.08,
        longitude=72.88,
        observation_date="2023-07-15",
    )

    assert reading is not None
    assert reading.location_name == "Mumbai"
    assert reading.observation_date == "2023-07-15"
    # Real values from this exact fixture, hand-verified against the raw
    # NetCDF this session (300.45037841796875 K -> 27.30C, etc.) — allow a
    # small tolerance for float32 storage round-tripping through the test.
    assert abs(reading.temp_2m_c - 27.30) < 0.01
    assert abs(reading.dewpoint_2m_c - 25.39) < 0.01
    assert abs(reading.wind_speed_10m_kmh - 16.00) < 0.05
    assert abs(reading.wind_direction_10m_deg - 247.32) < 0.1
    assert abs(reading.mslp_hpa - 1006.52) < 0.01
    assert abs(reading.precip_mm - 0.73) < 0.01


def test_returns_none_fields_gracefully_if_a_variable_is_absent():
    # A defensive check, not exercised by the fixture (which has all six
    # variables) — confirms the parser doesn't crash if a future request
    # variant omits one, consistent with Task 1's nullable columns.
    import zipfile
    import shutil
    import tempfile

    provider = CdsEra5Provider(client=None)
    with tempfile.TemporaryDirectory() as tmp:
        partial_zip = f"{tmp}/partial.zip"
        # Build a zip containing only the "instant" member from the real
        # fixture (drop "accum"/tp) — proves precip_mm comes back None
        # rather than crashing when one file is simply missing.
        with zipfile.ZipFile("tests/fixtures/era5_mumbai_sample.zip") as src:
            with zipfile.ZipFile(partial_zip, "w") as dst:
                for name in src.namelist():
                    if "instant" in name:
                        dst.writestr(name, src.read(name))

        reading = provider._parse_response(
            partial_zip, location_name="Mumbai", latitude=19.08, longitude=72.88,
            observation_date="2023-07-15",
        )
        assert reading.precip_mm is None
        assert reading.temp_2m_c is not None
```

- [ ] **Step 5: Run the test, verify it fails**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_era5_provider.py -v`
Expected: FAIL — `app.providers.era5` doesn't exist yet.

- [ ] **Step 6: Implement `backend/app/providers/era5.py`**

```python
"""CDS/ERA5 provider: fetches one (location, date) reading from the
Copernicus Climate Data Store's ERA5 reanalysis dataset. See this plan's
"Verified facts" section for the live research this is built from — real
observed latency, the zip-vs-plain-file response inconsistency, exact
variable/unit conventions, and the area/grid convention were all confirmed
against the real API, not assumed.

Deliberately synchronous and blocking (unlike every other provider in this
codebase) — this is only ever called from backend/scripts/seed_era5_history.py,
a standalone script a human runs once, never from a request handler or a
scheduled job. A real call takes 25 seconds to 2 minutes.
"""

import math
import os
import tempfile
import zipfile

import xarray as xr

from app.providers.historical import Era5ReadingData

CDS_DATASET_ID = "reanalysis-era5-single-levels"
CDS_URL = "https://cds.climate.copernicus.eu/api"

_VARIABLES = [
    "2m_temperature",
    "2m_dewpoint_temperature",
    "total_precipitation",
    "10m_u_component_of_wind",
    "10m_v_component_of_wind",
    "mean_sea_level_pressure",
]

# A generous box around the requested point — large enough that the
# nearest-grid-point lookup below always has real data to select from,
# small enough to stay well clear of CDS's large-area deprioritization
# (confirmed this session: ~1 degree boxes return in the same latency
# range as a single point).
_BOX_HALF_DEGREES = 0.5


def _clean(value) -> float | None:
    v = float(value)
    return v if math.isfinite(v) else None


class CdsEra5Provider:
    def __init__(self, client=None, api_key: str | None = None):
        self._owns_client = client is None
        if client is not None:
            self._client = client
        else:
            import ecmwf.datastores as eds
            from app.config import get_settings

            key = api_key if api_key is not None else get_settings().cds_api_key
            if not key:
                raise ValueError(
                    "CDS_API_KEY is not set. Register at https://cds.climate.copernicus.eu, "
                    "generate a key, and accept the Terms of Use for "
                    "'reanalysis-era5-single-levels' on that dataset's own page before "
                    "setting CDS_API_KEY in backend/.env."
                )
            os.environ["ECMWF_DATASTORES_URL"] = CDS_URL
            os.environ["ECMWF_DATASTORES_KEY"] = key
            self._client = eds.Client()

    def fetch_reading(
        self, location_name: str, latitude: float, longitude: float, observation_date: str
    ) -> Era5ReadingData | None:
        year, month, day = observation_date.split("-")
        request = {
            "product_type": "reanalysis",
            "variable": _VARIABLES,
            "year": year,
            "month": month,
            "day": day,
            "time": "12:00",
            "area": [
                latitude + _BOX_HALF_DEGREES,
                longitude - _BOX_HALF_DEGREES,
                latitude - _BOX_HALF_DEGREES,
                longitude + _BOX_HALF_DEGREES,
            ],
            "data_format": "netcdf",
        }
        with tempfile.TemporaryDirectory() as tmp:
            target = os.path.join(tmp, "era5_response")
            self._client.retrieve(CDS_DATASET_ID, request, target=target)
            return self._parse_response(target, location_name, latitude, longitude, observation_date)

    def _parse_response(
        self, path: str, location_name: str, latitude: float, longitude: float, observation_date: str
    ) -> Era5ReadingData:
        datasets = []
        if zipfile.is_zipfile(path):
            with tempfile.TemporaryDirectory() as extract_dir:
                with zipfile.ZipFile(path) as z:
                    z.extractall(extract_dir)
                for name in os.listdir(extract_dir):
                    datasets.append(xr.open_dataset(os.path.join(extract_dir, name), engine="h5netcdf").load())
        else:
            datasets.append(xr.open_dataset(path, engine="h5netcdf").load())

        merged = xr.merge(datasets, compat="override")
        point = merged.sel(latitude=latitude, longitude=longitude, method="nearest")

        def _var(name: str) -> float | None:
            if name not in point:
                return None
            return _clean(point[name].values[0])

        t2m_k = _var("t2m")
        d2m_k = _var("d2m")
        u10 = _var("u10")
        v10 = _var("v10")
        msl_pa = _var("msl")
        tp_m = _var("tp")

        wind_speed_kmh = wind_direction_deg = None
        if u10 is not None and v10 is not None:
            wind_speed_kmh = math.hypot(u10, v10) * 3.6
            wind_direction_deg = math.degrees(math.atan2(-u10, -v10)) % 360

        return Era5ReadingData(
            location_name=location_name,
            latitude=latitude,
            longitude=longitude,
            observation_date=observation_date,
            temp_2m_c=(t2m_k - 273.15) if t2m_k is not None else None,
            dewpoint_2m_c=(d2m_k - 273.15) if d2m_k is not None else None,
            precip_mm=(tp_m * 1000) if tp_m is not None else None,
            wind_speed_10m_kmh=wind_speed_kmh,
            wind_direction_10m_deg=wind_direction_deg,
            mslp_hpa=(msl_pa / 100) if msl_pa is not None else None,
        )

    def close(self) -> None:
        pass  # ecmwf.datastores.Client has no explicit close/session to release
```

Note: `CdsEra5Provider(client=None)` in the tests above passes `client=None` explicitly, which the constructor treats as "build a real client" — but the fixture-based tests call `_parse_response` directly (never `fetch_reading`), so the real-client construction path (which needs a real `CDS_API_KEY`) is never actually exercised by those tests. If this causes friction (e.g. the constructor still tries to import `ecmwf.datastores` even when unused), adjust by allowing tests to construct the provider with a trivial placeholder without triggering real client setup — use your judgment on the cleanest way to keep `_parse_response`-only tests fully independent of any credential or import requirement, while keeping `fetch_reading`'s real-usage path (used only by Task 3's seed script) correctly requiring a real client/key.

- [ ] **Step 7: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_era5_provider.py -v`
Expected: PASS, both tests.

- [ ] **Step 8: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 9: One real live end-to-end smoke test (manual, report the result — not a committed automated test)**

```python
from app.providers.era5 import CdsEra5Provider
provider = CdsEra5Provider()  # reads CDS_API_KEY from backend/.env via get_settings()
reading = provider.fetch_reading("Delhi", 28.61, 77.21, "2023-01-15")
print(reading)
```

This will take 25 seconds to 2 minutes (real CDS queue latency, confirmed this session) — run it as a background command, don't block on it inline. Confirm the returned values are physically sane for Delhi in mid-January (cool, dry winter — expect roughly 10-20°C, low precipitation).

- [ ] **Step 10: Add `cds_api_key` to `backend/app/config.py`**

Add `cds_api_key: str | None = None` to the `Settings` class, following the exact existing pattern for `bhashini_user_id`/etc.

- [ ] **Step 11: Commit**

```bash
git add backend/app/providers/historical.py backend/app/providers/era5.py backend/app/config.py backend/tests/test_era5_provider.py backend/tests/fixtures/era5_mumbai_sample.zip backend/requirements.txt backend/requirements.lock
git commit -m "feat: add HistoricalWeatherProvider protocol and CdsEra5Provider"
```

---

## Task 3: Seed script — populate real ERA5 data for a fixed (city, date) matrix

**Files:**
- Create: `backend/scripts/seed_era5_history.py`
- Test: `backend/tests/test_seed_era5_history.py`

**Interfaces:**
- Consumes: `CdsEra5Provider.fetch_reading(...)` (Task 2), `HistoricalWeatherReading` (Task 1).
- Produces: real rows in `historical_weather_readings`, consumed by Task 4's query service. Also produces `seed_era5_history(provider: HistoricalWeatherProvider, matrix: list[tuple[str, float, float, str]] | None = None) -> dict` (returns a summary: counts of succeeded/failed) — the module-level `LOCATIONS`/`DATES`/`MATRIX` constants below are the default when `matrix` isn't passed, so tests can inject a tiny fake matrix instead of the real 36-combination one.

- [ ] **Step 1: Write the failing tests (offline, fake provider — no real CDS calls)**

Create `backend/tests/test_seed_era5_history.py`:

```python
from datetime import datetime, timezone

from sqlalchemy import select

from app.db import get_engine
from app.models import HistoricalWeatherReading
from app.providers.historical import Era5ReadingData
from scripts.seed_era5_history import seed_era5_history


class _FakeProvider:
    def __init__(self, fail_for: set[tuple[str, str]] | None = None):
        self._fail_for = fail_for or set()

    def fetch_reading(self, location_name, latitude, longitude, observation_date):
        if (location_name, observation_date) in self._fail_for:
            raise RuntimeError("simulated CDS failure")
        return Era5ReadingData(
            location_name=location_name, latitude=latitude, longitude=longitude,
            observation_date=observation_date, temp_2m_c=25.0, dewpoint_2m_c=20.0,
            precip_mm=1.0, wind_speed_10m_kmh=10.0, wind_direction_10m_deg=180.0,
            mslp_hpa=1010.0,
        )


def test_seed_writes_a_row_per_matrix_entry(clean_historical_weather_readings):
    matrix = [("Mumbai", 19.08, 72.88, "2023-07-15"), ("Delhi", 28.61, 77.21, "2023-01-15")]
    summary = seed_era5_history(_FakeProvider(), matrix=matrix)

    assert summary["succeeded"] == 2
    assert summary["failed"] == 0

    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()
    assert {(r["location_name"], r["observation_date"]) for r in rows} == {
        ("Mumbai", "2023-07-15"), ("Delhi", "2023-01-15"),
    }


def test_seed_continues_past_a_single_failure_and_reports_it(clean_historical_weather_readings):
    matrix = [("Mumbai", 19.08, 72.88, "2023-07-15"), ("Delhi", 28.61, 77.21, "2023-01-15")]
    provider = _FakeProvider(fail_for={("Mumbai", "2023-07-15")})
    summary = seed_era5_history(provider, matrix=matrix)

    assert summary["succeeded"] == 1
    assert summary["failed"] == 1

    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()
    assert [r["location_name"] for r in rows] == ["Delhi"]


def test_seed_upserts_on_repeat_run_for_the_same_matrix_entry(clean_historical_weather_readings):
    matrix = [("Mumbai", 19.08, 72.88, "2023-07-15")]
    seed_era5_history(_FakeProvider(), matrix=matrix)
    seed_era5_history(_FakeProvider(), matrix=matrix)  # rerun — must not duplicate

    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()
    assert len(rows) == 1
```

Add a `clean_historical_weather_readings` fixture to `backend/tests/conftest.py`, mirroring the exact existing `_truncate(Model)` pattern used by every other table's fixture (e.g. `clean_gfs_forecast_points`).

- [ ] **Step 2: Run tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_seed_era5_history.py -v`
Expected: FAIL — `scripts.seed_era5_history` doesn't exist yet.

- [ ] **Step 3: Implement `backend/scripts/seed_era5_history.py`**

```python
"""One-time seed script for ERA5 historical weather data — NOT part of the
FastAPI app, NOT registered with IngestionScheduler, NOT run by the
automated test suite. Run manually, once (or occasionally, to extend
coverage), by a human, from backend/: `python scripts/seed_era5_history.py`.

A real CDS request takes 25 seconds to 2 minutes (confirmed live — see
docs/superpowers/plans/2026-09-08-era5-historical-provider.md's "Verified
facts"). This script's default matrix (6 cities x 6 dates = 36 requests)
takes roughly 20-40 minutes end to end. This is expected and fine — this
script is meant to be run once, not integrated into any fast path.
"""

import logging
import sys
from datetime import datetime, timezone

from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import HistoricalWeatherReading
from app.providers.historical import HistoricalWeatherProvider

logger = logging.getLogger(__name__)

LOCATIONS = [
    ("Mumbai", 19.08, 72.88),
    ("Delhi", 28.61, 77.21),
    ("Chennai", 13.08, 80.27),
    ("Bangalore", 12.97, 77.59),
    ("Kolkata", 22.57, 88.36),
    ("Hyderabad", 17.39, 78.49),
]

DATES = [
    "2023-01-15",  # winter
    "2023-04-15",  # pre-monsoon
    "2023-07-15",  # monsoon
    "2023-10-15",  # post-monsoon
    "2024-01-15",  # winter, second year
    "2024-07-15",  # monsoon, second year
]

DEFAULT_MATRIX = [
    (name, lat, lon, date) for (name, lat, lon) in LOCATIONS for date in DATES
]

_MUTABLE_COLUMNS = (
    "latitude", "longitude", "temp_2m_c", "dewpoint_2m_c", "precip_mm",
    "wind_speed_10m_kmh", "wind_direction_10m_deg", "mslp_hpa", "fetched_at",
)


def seed_era5_history(
    provider: HistoricalWeatherProvider, matrix: list[tuple[str, float, float, str]] | None = None
) -> dict:
    matrix = matrix if matrix is not None else DEFAULT_MATRIX
    succeeded = 0
    failed = 0

    for i, (location_name, latitude, longitude, observation_date) in enumerate(matrix, start=1):
        logger.info(
            "[%d/%d] Fetching %s on %s...", i, len(matrix), location_name, observation_date
        )
        try:
            reading = provider.fetch_reading(location_name, latitude, longitude, observation_date)
        except Exception:
            logger.exception("Failed to fetch %s on %s", location_name, observation_date)
            failed += 1
            continue

        fetched_at = datetime.now(timezone.utc)
        with get_engine().begin() as conn:
            stmt = pg_insert(HistoricalWeatherReading).values(
                location_name=reading.location_name,
                latitude=reading.latitude,
                longitude=reading.longitude,
                observation_date=reading.observation_date,
                temp_2m_c=reading.temp_2m_c,
                dewpoint_2m_c=reading.dewpoint_2m_c,
                precip_mm=reading.precip_mm,
                wind_speed_10m_kmh=reading.wind_speed_10m_kmh,
                wind_direction_10m_deg=reading.wind_direction_10m_deg,
                mslp_hpa=reading.mslp_hpa,
                fetched_at=fetched_at,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[
                    HistoricalWeatherReading.location_name,
                    HistoricalWeatherReading.observation_date,
                ],
                set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
            )
            conn.execute(stmt)
        succeeded += 1
        logger.info("[%d/%d] Saved %s on %s", i, len(matrix), location_name, observation_date)

    logger.info("Done: %d succeeded, %d failed out of %d", succeeded, failed, len(matrix))
    return {"succeeded": succeeded, "failed": failed, "total": len(matrix)}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    from app.providers.era5 import CdsEra5Provider

    provider = CdsEra5Provider()
    summary = seed_era5_history(provider)
    sys.exit(0 if summary["failed"] == 0 else 1)
```

Note: this script imports `app.*` modules, so it must be run with `backend/` as the working directory and the venv active (`python scripts/seed_era5_history.py` from `backend/`), matching how `alembic` and every other script in this project is invoked.

- [ ] **Step 4: Run the offline tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_seed_era5_history.py -v`
Expected: PASS, all 3 tests.

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 6: Commit the script and its tests**

```bash
git add backend/scripts/seed_era5_history.py backend/tests/test_seed_era5_history.py backend/tests/conftest.py
git commit -m "feat: add ERA5 historical data seed script"
```

- [ ] **Step 7: RUN THE REAL SEED — this is the actual deliverable of this task, not an optional check**

From `backend/`, with the real venv active and `CDS_API_KEY` set in `.env`:

```bash
python scripts/seed_era5_history.py
```

**This takes approximately 20-40 minutes of real wall-clock time (36 real CDS requests at 25s-2min each).** Run it as a background command — do not block waiting on it, and do not attempt to shorten the matrix to make it finish faster; the whole point of this task is real production data for real demo cities across real seasons. Report the final summary (succeeded/failed counts) and, if any requests failed, whether re-running the script (safe — it upserts, never duplicates) resolved them.

After it completes, verify with a real query:
```sql
SELECT location_name, observation_date, temp_2m_c, precip_mm FROM historical_weather_readings ORDER BY location_name, observation_date;
```
Confirm 36 rows (or fewer, if some genuinely failed after a retry) with physically sane values (e.g. Delhi in January noticeably cooler than Delhi in July; Chennai/Kolkata monsoon dates showing real measurable precipitation).

- [ ] **Step 8: Commit nothing further here** — the seed run writes to the shared Postgres database directly, not to any file in the repo. Task 4 reads that data at query time.

---

## Task 4: `get_historical_weather` query service + `GET /historical` endpoint + chat tool

**Files:**
- Create: `backend/app/history/__init__.py`
- Create: `backend/app/history/service.py`
- Modify: `backend/app/main.py`
- Modify: `backend/app/chat/tools.py`, `backend/app/chat/service.py` (system prompt)
- Test: `backend/tests/test_history_service.py`, `backend/tests/test_history_endpoint.py`, additions to `backend/tests/test_chat_tools.py`

**Interfaces:**
- Consumes: `HistoricalWeatherReading` rows written by Task 3's seed script (already real data in the shared dev database by the time this task runs).
- Produces: `get_historical_weather(location_name: str, observation_date: str) -> dict | None` — case-insensitive match on `location_name`, returns `None` if no seeded row exists for that exact (location, date) pair (this is expected and common — the seeded matrix is small and fixed; callers, especially the chat tool, must handle this gracefully, not treat it as an error).

- [ ] **Step 1: Write the failing tests for the service**

Create `backend/tests/test_history_service.py`:

```python
from datetime import datetime, timezone

from sqlalchemy import insert

from app.db import get_engine
from app.history.service import get_historical_weather
from app.models import HistoricalWeatherReading


def _seed_row(**overrides):
    base = dict(
        location_name="Mumbai", latitude=19.08, longitude=72.88,
        observation_date="2023-07-15", temp_2m_c=27.3, dewpoint_2m_c=25.4,
        precip_mm=0.73, wind_speed_10m_kmh=16.0, wind_direction_10m_deg=247.3,
        mslp_hpa=1006.5, fetched_at=datetime.now(timezone.utc),
    )
    base.update(overrides)
    with get_engine().begin() as conn:
        conn.execute(insert(HistoricalWeatherReading).values(**base))


def test_returns_the_seeded_reading_for_an_exact_match(clean_historical_weather_readings):
    _seed_row()
    result = get_historical_weather("Mumbai", "2023-07-15")
    assert result is not None
    assert result["temp_2m_c"] == 27.3
    assert result["precip_mm"] == 0.73


def test_match_is_case_insensitive_on_location_name(clean_historical_weather_readings):
    _seed_row(location_name="Mumbai")
    result = get_historical_weather("mumbai", "2023-07-15")
    assert result is not None


def test_returns_none_for_an_unseeded_combination(clean_historical_weather_readings):
    _seed_row(location_name="Mumbai", observation_date="2023-07-15")
    assert get_historical_weather("Mumbai", "2023-07-16") is None
    assert get_historical_weather("Pune", "2023-07-15") is None


def test_no_raw_payload_or_id_in_response(clean_historical_weather_readings):
    _seed_row()
    result = get_historical_weather("Mumbai", "2023-07-15")
    assert "id" not in result
    assert "raw_payload" not in result
```

- [ ] **Step 2: Run tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_history_service.py -v`
Expected: FAIL — `app.history.service` doesn't exist.

- [ ] **Step 3: Implement `backend/app/history/service.py`**

```python
"""Query-path read of the ERA5 data seeded by
backend/scripts/seed_era5_history.py. This is the only reader of
historical_weather_readings — no live CDS call ever happens here, or
anywhere in the request path (see this plan's Global Constraints).
A miss (an unseeded location/date combination) is an expected, common
outcome given the small fixed seed matrix, not an error.
"""

from sqlalchemy import func, select

from app.db import get_engine
from app.models import HistoricalWeatherReading

_RESPONSE_FIELDS = (
    "location_name", "latitude", "longitude", "observation_date",
    "temp_2m_c", "dewpoint_2m_c", "precip_mm", "wind_speed_10m_kmh",
    "wind_direction_10m_deg", "mslp_hpa",
)


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def get_historical_weather(location_name: str, observation_date: str) -> dict | None:
    with get_engine().connect() as conn:
        row = (
            conn.execute(
                select(HistoricalWeatherReading).where(
                    func.lower(HistoricalWeatherReading.location_name) == location_name.lower(),
                    HistoricalWeatherReading.observation_date == observation_date,
                )
            )
            .mappings()
            .first()
        )

    if row is None:
        return None
    return _to_response(row)
```

- [ ] **Step 4: Run tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_history_service.py -v`
Expected: PASS.

- [ ] **Step 5: Add the `GET /historical` endpoint**

In `backend/app/main.py`:

```python
from app.history.service import get_historical_weather

@app.get("/historical")
def historical_weather_endpoint(
    location: str = Query(..., min_length=1),
    date: str = Query(..., min_length=10, max_length=10),
) -> dict:
    result = get_historical_weather(location, date)
    if result is None:
        raise HTTPException(
            status_code=404,
            detail=(
                f"No historical data for '{location}' on {date}. This dataset only covers "
                "a small pre-seeded set of major Indian cities and sample dates — see "
                "backend/scripts/seed_era5_history.py's LOCATIONS/DATES for exact coverage."
            ),
        )
    return result
```

Create `backend/tests/test_history_endpoint.py` (mirror `test_nwp_endpoint.py`'s exact pattern — seed a real row via `insert(HistoricalWeatherReading)`, hit the endpoint, assert on the response; plus a test asserting a 404 with a helpful message for an unseeded combination).

- [ ] **Step 6: Add the chat tool**

In `backend/app/chat/tools.py`, add a `ToolSpec` named `get_historical_weather` with a description that's explicit about the limited, fixed coverage — this matters more here than for any other tool in this codebase, since a wrong assumption ("this covers any date") would make the LLM confidently promise data that doesn't exist:

```
"Get historical weather (temperature, precipitation, wind, pressure) for a specific major
Indian city on a specific past date, from ERA5 reanalysis data. IMPORTANT: this only covers
a small, fixed, pre-seeded set of cities and sample dates (not arbitrary locations/dates) —
if this tool returns not-found, tell the user this specific city/date combination isn't in
the pre-loaded historical dataset, don't imply historical data doesn't exist at all."
```

with `location` and `date` (format `"YYYY-MM-DD"`) both required. Add the handler (calling `get_historical_weather`, returning `{"error": "..."}` in the same in-band-error style as every other tool handler in this file when the result is `None`) and register it in `_HANDLERS`. Update the existing "cover all N tool names" test in `tests/test_chat_tools.py` to include it (rename, don't duplicate — follow this file's own established precedent from the GFS and advisory-Skills sprints).

Update the system prompt in `app/chat/service.py` with a short paragraph mentioning `get_historical_weather` and its limited-coverage caveat.

- [ ] **Step 7: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 8: Manual live verification (real data, already seeded by Task 3 — no live CDS call needed here)**

Query `/historical?location=Mumbai&date=2023-07-15` against the real seeded database and confirm a sane real response comes back. Also query an intentionally-unseeded combination (e.g. `/historical?location=Mumbai&date=2020-01-01`) and confirm a clean 404 with the helpful message.

- [ ] **Step 9: Commit**

```bash
git add backend/app/history/ backend/app/main.py backend/app/chat/tools.py backend/app/chat/service.py backend/tests/test_history_service.py backend/tests/test_history_endpoint.py backend/tests/test_chat_tools.py
git commit -m "feat: add get_historical_weather query service, GET /historical endpoint, and chat tool"
```
