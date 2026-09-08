# GFS/NWP Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `NWPProvider` the V1 spec requires (§4: "GFS via the public, unauthenticated AWS S3 bucket `noaa-gfs-bdp-pds`... parsed server-side with `cfgrib`/`xarray` during ingestion, not per-request") — a scheduled ingestion job that fetches the latest GFS model run, extracts a handful of surface fields cropped to India, and a query service/chat tool/endpoint exposing it.

**Architecture:** GFS introduces a FIFTH query-path pattern, distinct from the four already in this codebase (scheduled-broadcast/reconciliation — SACHET/PFZ; cache-with-TTL point-lookup — Open-Meteo/METAR; permanent-cache — geocoding; never-cached chat). GFS is **scheduled-ingestion of a regular grid, reconciled by model run**: each ingestion cycle discovers the latest published GFS run, fetches ~10 surface fields at 6 forecast hours cropped to India's bounding box (6-38°N, 68-98°E — a 129×121 = 15,609-point regular 0.25° grid, confirmed live), writes them to Postgres, and deletes every row from any OLDER run (mirrors the reconciliation pattern already used by `app/ingestion/alerts.py`/`marine.py`, but reconciling by `(run_date, run_hour)` instead of by fetch-presence). Query-time lookups snap an arbitrary (lat, lon) to the nearest actual 0.25°-grid point mathematically (`round(x * 4) / 4`) — no live provider call ever happens at query time, matching every other broadcast-style source in this codebase.

**Tech Stack:** `cfgrib==0.9.15.1` + `eccodes==2.48.0` (both live-verified this session: `eccodes` ships a prebuilt `win_amd64`/`cp313` wheel — no system ecCodes install, no conda, no WSL needed on this project's Windows dev environment) + `xarray` for GRIB2 parsing. `httpx` (already a dependency) for HTTP Range GET fetches against the public S3 bucket — no AWS SDK, no credentials.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md

## Verified facts (live, this session — not assumed)

All verified by actually listing the bucket, downloading real files, and opening them with cfgrib:

- **Bucket structure**: `https://noaa-gfs-bdp-pds.s3.amazonaws.com/gfs.<YYYYMMDD>/<HH>/atmos/gfs.t<HH>z.pgrb2.<res>.f<HHH>` where `<HH>` ∈ {00,06,12,18}, `<res>` ∈ {0p25,0p50,1p00}, `<HHH>` = zero-padded forecast hour (000, 003, 024, ...). Each file has a sidecar plain-text index at the same key + `.idx`.
- **The newest cycle can legitimately not exist yet** — confirmed live (checked 2026-09-08 morning UTC: that day's `gfs.20260908/` had zero keys, only the previous day's four cycles existed). The provider MUST discover the latest actually-published run, not assume `today 00Z`.
- **`.idx` format** (plain text, one line per GRIB message): `<seq>:<start_byte>:d=<YYYYMMDDHH>:<PARAM>:<LEVEL>:<STEP>:` — e.g. `580:414284316:d=2026090712:TMP:2 m above ground:anl:`. A message's byte length = next line's start byte minus this line's start byte (or EOF for the last message). **The `<STEP>` field changes with forecast hour** (`anl` only at f000; something like `N hour fcst` at f024+) — match on `<PARAM>:<LEVEL>:` prefix, never the full line, so the same matching code works at every forecast hour.
- **HTTP Range GET works against the live bucket** — confirmed with a real `curl -H "Range: bytes=X-Y"` request returning a real `206 Partial Content` with exactly the requested message bytes, openable by cfgrib. This is how the provider fetches ONE field without downloading the ~480MB (0.25°) whole-file.
- **A single GRIB2 message opens standalone with cfgrib** — confirmed: a 511,502-byte single-message slice (the `TMP:2 m above ground` field, byte-sliced exactly as described above from a real downloaded file) opens with `xarray.open_dataset(path, engine="cfgrib")` and returns a real, sane value (28.46°C over Mumbai at a real analysis time). This exact byte-sliced file is committed as a test fixture — see Task 2.
- **Grid orientation** (confirmed from opening the real fixture): `latitude` descends 90.0 → -89.75 → ... → -90.0 in 0.25° steps (721 points); `longitude` ascends 0.0 → 359.75 in 0.25° steps (1440 points), i.e. **0-360°E convention, not -180/180** — India's 68-98°E range needs no dateline handling. Cropping to India in xarray: `ds.sel(latitude=slice(38, 6), longitude=slice(68, 98))` (latitude slice is high-to-low because the data itself is ordered high-to-low; longitude slice is low-to-high).
- **Exact field:level identifiers confirmed live** (from the real `.idx`, f000/analysis; the `<STEP>` suffix will differ at other forecast hours per above, but the `PARAM:LEVEL:` prefix is stable): `PRMSL:mean sea level`, `GUST:surface`, `TMP:2 m above ground`, `RH:2 m above ground`, `UGRD:10 m above ground`, `VGRD:10 m above ground`, `PRATE:surface`, `CAPE:surface`, `CIN:surface`, `TCDC:entire atmosphere`. `PRATE` (instantaneous rate) is present at every forecast hour including f000; `APCP` (accumulated precipitation) is NOT present at f000 (needs an accumulation window) — **this plan deliberately uses only `PRATE`, not `APCP`, specifically to avoid a field that's absent at one of the six target forecast hours.**
- **cfgrib requires one `filter_by_keys={"typeOfLevel":..., "level":...}` per homogeneous group** — a single pgrb2 file mixes dozens of incompatible level types in one file, and `xarray.open_dataset(..., engine="cfgrib")` cannot open a whole file in one call. The ten fields above fall into (at most) five typeOfLevel groups: `heightAboveGround`+level=2 (TMP, RH — **verified live**, see the committed fixture), `heightAboveGround`+level=10 (UGRD, VGRD — same typeOfLevel as the verified group, high confidence), `surface`+level=0 (GUST, PRATE, CAPE, CIN), `meanSea`+level=0 (PRMSL), and whatever cfgrib names "entire atmosphere" for TCDC (commonly `atmosphereSingleLayer`, but confirm live — see Task 2 Step 6's mandatory live-verification checkpoint). **Task 2 must live-verify the exact `filter_by_keys` value for the three groups not yet confirmed by this session's research** (surface, meanSea, and TCDC's level type) by actually fetching and opening each against the real bucket — this is not blocked by any missing credential (the bucket is public), so there's no reason to defer it to a non-blocking manual step; get it right during implementation.
- **Scale**: 6 forecast hours (f000, f024, f048, f072, f096, f120 — chosen as a 5-day-ahead daily outlook; all confirmed to exist as real files) × ~10 fields × 15,609 India grid points × 4 runs/day (following the spec's own stated cadence, "once per model run") ≈ 3.7M values/day. Because only the LATEST run is ever kept (reconciliation, not accumulation — see Task 3), steady-state storage is capped at one run's worth (93,654 rows: 15,609 points × 6 forecast hours, with the 10 fields as columns on one row per point+hour, not one row per field — see Task 1's schema) regardless of how long the app runs.

## Global Constraints

- No LLM call, no raw provider call from any query-path service — `app/nwp/service.py` reads only from Postgres, exactly like every other query-path service in this codebase.
- `cfgrib==0.9.15.1` and `eccodes==2.48.0` pinned EXACTLY (not a loose range) in `requirements.txt`/`requirements.lock` — an unpinned resolver could pick an `eccodes` version with no `win_amd64` wheel and fall back to a source build with no working Windows toolchain path.
- Tests never make a real network call — GRIB2 parsing tests use the committed fixture at `backend/tests/fixtures/gfs_t2m_sample.grib2` (real data, captured this session, ~500KB); ingestion/discovery tests mock `httpx`. One manual live-verification step is expected and required during Task 2 (see above) — the bucket needs no credentials, so this is a real verification step during implementation, not deferred as "blocked."
- No `raw_payload` JSONB column on the new table — deliberate deviation from this codebase's usual per-provider convention (every other provider stores `raw_payload` for debugging/forward-compat on externally-sourced, loosely-structured data). GFS field values are already fully-typed scalar columns with well-documented units fixed in code; there is no unpredictable upstream schema to guard against the way there is for e.g. SACHET's undocumented alert feed, and storing a redundant payload blob per row across ~937,000 rows has a real storage cost with no corresponding debugging value here.
- Reconciliation is by `(run_date, run_hour)`, not by `external_id` presence (unlike SACHET/PFZ) — a new run fully replaces the old one; there's no concept of an individual GFS grid point being "resolved" independently of its run.
- India bounding box: latitude 6 to 38 (inclusive), longitude 68 to 98 (inclusive) — used consistently by the provider (cropping) and the query service (validating an incoming coordinate is in-bounds before snapping).

---

## Task 1: `GfsForecastPoint` model + Alembic migration

**Files:**
- Modify: `backend/app/models.py`
- Create: Alembic migration (run `alembic revision --autogenerate -m "add gfs_forecast_points table"` after adding the model, from `backend/`)
- Test: `backend/tests/test_gfs_forecast_points_table_schema.py`

**Interfaces:**
- Produces: `GfsForecastPoint` ORM model, table `gfs_forecast_points`, with a unique constraint on `(run_date, run_hour, forecast_hour, grid_latitude, grid_longitude)` — Task 3's ingestion upserts against this constraint, Task 3's reconciliation deletes by `(run_date, run_hour)`, Task 4's query service selects by `(grid_latitude, grid_longitude, forecast_hour)` against whatever the latest `(run_date, run_hour)` currently in the table is.

- [ ] **Step 1: Add the model to `backend/app/models.py`**

```python
class GfsForecastPoint(Base):
    __tablename__ = "gfs_forecast_points"
    __table_args__ = (
        UniqueConstraint(
            "run_date", "run_hour", "forecast_hour", "grid_latitude", "grid_longitude",
            name="uq_gfs_forecast_points_run_hour_point",
        ),
    )

    id = Column(Integer, primary_key=True)
    run_date = Column(String, nullable=False, index=True)
    run_hour = Column(String, nullable=False)
    forecast_hour = Column(Integer, nullable=False)
    valid_time = Column(DateTime(timezone=True), nullable=False)
    grid_latitude = Column(Float, nullable=False, index=True)
    grid_longitude = Column(Float, nullable=False, index=True)
    temp_2m_c = Column(Float, nullable=True)
    relative_humidity_2m_pct = Column(Float, nullable=True)
    wind_speed_10m_kmh = Column(Float, nullable=True)
    wind_direction_10m_deg = Column(Float, nullable=True)
    wind_gust_kmh = Column(Float, nullable=True)
    precip_rate_mmh = Column(Float, nullable=True)
    cape_j_per_kg = Column(Float, nullable=True)
    cin_j_per_kg = Column(Float, nullable=True)
    cloud_cover_pct = Column(Float, nullable=True)
    mslp_hpa = Column(Float, nullable=True)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
```

All ten field columns are `nullable=True` deliberately: if any single field-group fetch fails for one forecast hour (a partial GRIB2 parse failure, a field renamed upstream), the ingestion job should still write the fields it DID get for that grid point rather than dropping the whole row — a partial forecast is more useful than none, consistent with this codebase's general "prefer stale/partial over broken" posture (see e.g. `app/forecast/service.py`'s partial-stale-cache fallback).

- [ ] **Step 2: Write the failing schema test**

Create `backend/tests/test_gfs_forecast_points_table_schema.py`:

```python
from sqlalchemy import inspect

from app.db import get_engine


def test_gfs_forecast_points_table_has_expected_columns():
    inspector = inspect(get_engine())
    columns = {col["name"] for col in inspector.get_columns("gfs_forecast_points")}
    assert columns == {
        "id", "run_date", "run_hour", "forecast_hour", "valid_time",
        "grid_latitude", "grid_longitude", "temp_2m_c", "relative_humidity_2m_pct",
        "wind_speed_10m_kmh", "wind_direction_10m_deg", "wind_gust_kmh",
        "precip_rate_mmh", "cape_j_per_kg", "cin_j_per_kg", "cloud_cover_pct",
        "mslp_hpa", "fetched_at",
    }


def test_gfs_forecast_points_has_composite_unique_constraint():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("gfs_forecast_points")
    names = {frozenset(c["column_names"]) for c in constraints}
    assert frozenset(
        {"run_date", "run_hour", "forecast_hour", "grid_latitude", "grid_longitude"}
    ) in names
```

- [ ] **Step 3: Run test, verify it fails**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gfs_forecast_points_table_schema.py -v`
Expected: FAIL — table doesn't exist yet (no migration applied).

- [ ] **Step 4: Generate and apply the Alembic migration**

```bash
cd backend
.venv/Scripts/python.exe -m alembic revision --autogenerate -m "add gfs_forecast_points table"
.venv/Scripts/python.exe -m alembic upgrade head
```

Read the generated migration file and confirm it matches the model exactly (autogenerate has been reliable elsewhere in this codebase, but always verify — this is standard practice for every migration in this project).

- [ ] **Step 5: Run test, verify it passes**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gfs_forecast_points_table_schema.py -v`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS (288 pre-existing + 2 new).

- [ ] **Step 7: Commit**

```bash
git add backend/app/models.py backend/alembic/versions/ backend/tests/test_gfs_forecast_points_table_schema.py
git commit -m "feat: add gfs_forecast_points table"
```

---

## Task 2: `NWPProvider` protocol + `NoaaGfsProvider` (GFS discovery, fetch, and GRIB2 parsing)

**Files:**
- Create: `backend/app/providers/nwp.py` (protocol + dataclasses)
- Create: `backend/app/providers/gfs.py` (`NoaaGfsProvider`)
- Create: `backend/tests/fixtures/gfs_t2m_sample.grib2` (already extracted this session — copy from the research scratch space; see Step 1)
- Test: `backend/tests/test_gfs_provider.py`
- Modify: `backend/requirements.txt`, `backend/requirements.lock`

**Interfaces:**
- Produces: `GfsGridPointData` dataclass (fields matching Task 1's model columns minus `id`/`fetched_at`, plus `run_date: str`, `run_hour: str`, `forecast_hour: int`, `valid_time: datetime`, `grid_latitude: float`, `grid_longitude: float`). `NoaaGfsProvider.discover_latest_run() -> tuple[str, str]` (returns `(run_date, run_hour)`, e.g. `("20260907", "12")`). `NoaaGfsProvider.fetch_india_grid(run_date: str, run_hour: str, forecast_hour: int) -> list[GfsGridPointData]` — Task 3's ingestion job calls this once per target forecast hour.
- Consumes: nothing from earlier tasks (this is the provider layer).

This is the highest-risk, most novel task in this plan — the only one requiring genuine live-verification during implementation (not just transcription). Take the verification steps seriously; do not skip them because "it probably works the same as the verified group."

- [ ] **Step 1: Copy the pre-captured test fixture into the repo**

A real, valid, standalone GRIB2 message (the `TMP:2 m above ground` field from a real GFS run, byte-sliced from a real downloaded file using its real `.idx` byte offsets, confirmed this session to open correctly with cfgrib) already exists at:
`C:\Users\ACER\AppData\Local\Temp\claude\gfs_research\t2m_message.grib2` — **do NOT use this file, it's 2.27MB (0.25° resolution).**

Instead, extract a smaller one yourself (still fully real data, no network needed — the source file is already on disk from this session's research):

```python
start, end = 414284316, 414795818  # TMP:2 m above ground, confirmed via the real .idx
with open(r"C:\Users\ACER\AppData\Local\Temp\claude\gfs_research\gfs.t12z.pgrb2.0p25.f000", "rb") as f:
    f.seek(start)
    data = f.read(end - start)
with open("backend/tests/fixtures/gfs_t2m_sample.grib2", "wb") as out:
    out.write(data)
```

This produces a 511,502-byte file starting with `GRIB` — already verified this session to open with `xarray.open_dataset(path, engine="cfgrib")` and return `t2m` values (a real 28.46°C reading over Mumbai). If the source file at the path above is no longer present on this machine (e.g. temp directory cleaned), instead perform ONE live fetch of the same field from the real bucket to recreate it — this is unauthenticated and always available; see Step 6 for the exact discovery/range-fetch pattern to use.

- [ ] **Step 2: Pin the new dependencies**

Add to `backend/requirements.txt`:
```
cfgrib==0.9.15.1
eccodes==2.48.0
xarray>=2024.1.0
```

Add to `backend/requirements.lock` (exact versions, alphabetically ordered among the existing entries):
```
cfgrib==0.9.15.1
eccodes==2.48.0
xarray==<whatever version pip resolves — run pip install and capture the real resolved version>
```

Run `.venv/Scripts/python.exe -m pip install -r requirements.lock` and confirm all three import cleanly: `python -c "import cfgrib, eccodes, xarray"`.

- [ ] **Step 3: Write the protocol and dataclass in `backend/app/providers/nwp.py`**

```python
"""NWPProvider: Numerical Weather Prediction data (spec section 4's "NWP"
requirement, satisfied via GFS). Distinct from WeatherProvider (Open-Meteo,
point-queried, generously rate-limited, live-fallback-on-cache-miss) — GFS
is a bounded, scheduled-broadcast source like SACHET/INCOIS: the whole grid
for the latest model run is fetched on ingestion, never per-request.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol


@dataclass
class GfsGridPointData:
    run_date: str
    run_hour: str
    forecast_hour: int
    valid_time: datetime
    grid_latitude: float
    grid_longitude: float
    temp_2m_c: float | None
    relative_humidity_2m_pct: float | None
    wind_speed_10m_kmh: float | None
    wind_direction_10m_deg: float | None
    wind_gust_kmh: float | None
    precip_rate_mmh: float | None
    cape_j_per_kg: float | None
    cin_j_per_kg: float | None
    cloud_cover_pct: float | None
    mslp_hpa: float | None


class NWPProvider(Protocol):
    def discover_latest_run(self) -> tuple[str, str]: ...
    def fetch_india_grid(self, run_date: str, run_hour: str, forecast_hour: int) -> list[GfsGridPointData]: ...
```

- [ ] **Step 4: Write the failing tests for run discovery**

Create `backend/tests/test_gfs_provider.py`. Run discovery must try the four synoptic hours of "today" (UTC) from newest to oldest, then fall back to "yesterday"'s 18Z, checking each candidate's `.idx` file with an HTTP HEAD (a HEAD on a real S3 object key returns 200 if it exists, 404 if not — cheaper than a GET):

```python
from datetime import datetime, timezone
from unittest.mock import MagicMock

import httpx
import pytest

from app.providers.gfs import NoaaGfsProvider


def _mock_client(head_responses: dict[str, int]) -> MagicMock:
    client = MagicMock()

    def _head(url, **kwargs):
        for key, status in head_responses.items():
            if key in url:
                return httpx.Response(status_code=status, request=httpx.Request("HEAD", url))
        return httpx.Response(status_code=404, request=httpx.Request("HEAD", url))

    client.head.side_effect = _head
    return client


def test_discover_latest_run_finds_newest_available_cycle(monkeypatch):
    fixed_now = datetime(2026, 9, 8, 5, 0, tzinfo=timezone.utc)  # 05:00 UTC — 00Z of today should exist by now
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({"gfs.20260908/00": 200})

    provider = NoaaGfsProvider(client=client)
    run_date, run_hour = provider.discover_latest_run()

    assert (run_date, run_hour) == ("20260908", "00")


def test_discover_latest_run_falls_back_when_newest_cycle_not_yet_published(monkeypatch):
    # It's 13:00 UTC — the 12Z cycle would normally be expected, but hasn't
    # actually been published yet (confirmed live behavior this session:
    # the newest cycle can legitimately not exist).
    fixed_now = datetime(2026, 9, 8, 13, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({"gfs.20260908/06": 200})  # 12Z missing, 06Z exists

    provider = NoaaGfsProvider(client=client)
    run_date, run_hour = provider.discover_latest_run()

    assert (run_date, run_hour) == ("20260908", "06")


def test_discover_latest_run_falls_back_to_previous_day(monkeypatch):
    fixed_now = datetime(2026, 9, 8, 1, 0, tzinfo=timezone.utc)  # very early — even 00Z today may be missing
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({"gfs.20260907/18": 200})

    provider = NoaaGfsProvider(client=client)
    run_date, run_hour = provider.discover_latest_run()

    assert (run_date, run_hour) == ("20260907", "18")


def test_discover_latest_run_raises_when_nothing_found(monkeypatch):
    fixed_now = datetime(2026, 9, 8, 5, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({})  # nothing exists — every HEAD 404s

    provider = NoaaGfsProvider(client=client)
    with pytest.raises(RuntimeError, match="No recent GFS run"):
        provider.discover_latest_run()
```

- [ ] **Step 5: Run tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gfs_provider.py -v`
Expected: FAIL — `app.providers.gfs` doesn't exist yet.

- [ ] **Step 6: Implement discovery and byte-range fetch in `backend/app/providers/gfs.py`**

```python
"""NOAA GFS provider: discovers the latest published model run on the
public, unauthenticated S3 bucket noaa-gfs-bdp-pds, fetches a handful of
surface fields at 6 forecast hours cropped to India via HTTP Range GET
(never downloading a whole ~480MB global file), and parses them with
cfgrib/xarray. See this plan's "Verified facts" section for the live
research this is built from — bucket structure, .idx format, grid
orientation, and exact field:level identifiers were all confirmed against
the real bucket, not assumed.
"""

import io
import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import httpx
import xarray as xr

from app.providers.nwp import GfsGridPointData
from app.providers.retry import call_with_retries

GFS_BASE_URL = "https://noaa-gfs-bdp-pds.s3.amazonaws.com"

_SYNOPTIC_HOURS = ("18", "12", "06", "00")  # newest-first within a day
_INDIA_LAT_RANGE = (6.0, 38.0)
_INDIA_LON_RANGE = (68.0, 98.0)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _run_key(run_date: str, run_hour: str, forecast_hour: int) -> str:
    return f"gfs.{run_date}/{run_hour}/atmos/gfs.t{run_hour}z.pgrb2.0p25.f{forecast_hour:03d}"


@dataclass
class _FieldGroup:
    filter_by_keys: dict
    # (grib_param, idx_level_text) -> output attribute name on GfsGridPointData
    fields: dict[tuple[str, str], str]


class NoaaGfsProvider:
    def __init__(self, client: httpx.Client | None = None):
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=30.0)

    def discover_latest_run(self) -> tuple[str, str]:
        now = _utcnow()
        candidates: list[tuple[str, str]] = []
        for hour in _SYNOPTIC_HOURS:
            if int(hour) <= now.hour:
                candidates.append((now.strftime("%Y%m%d"), hour))
        yesterday = now - timedelta(days=1)
        for hour in _SYNOPTIC_HOURS:
            candidates.append((yesterday.strftime("%Y%m%d"), hour))

        for run_date, run_hour in candidates:
            idx_url = f"{GFS_BASE_URL}/{_run_key(run_date, run_hour, 0)}.idx"
            response = call_with_retries(lambda url=idx_url: self._client.head(url))
            if response.status_code == 200:
                return run_date, run_hour

        raise RuntimeError("No recent GFS run found in the last two days of synoptic cycles")

    def _fetch_idx(self, run_date: str, run_hour: str, forecast_hour: int) -> str:
        idx_url = f"{GFS_BASE_URL}/{_run_key(run_date, run_hour, forecast_hour)}.idx"
        response = call_with_retries(lambda: self._client.get(idx_url))
        response.raise_for_status()
        return response.text

    def _byte_range_for(self, idx_text: str, param: str, level_text: str) -> tuple[int, int | None]:
        lines = idx_text.strip().splitlines()
        starts = [int(line.split(":")[1]) for line in lines]
        for i, line in enumerate(lines):
            parts = line.split(":")
            if parts[3] == param and parts[4] == level_text:
                start = starts[i]
                end = starts[i + 1] if i + 1 < len(starts) else None
                return start, end
        raise ValueError(f"Field '{param}:{level_text}' not found in this forecast hour's index")

    def _fetch_field_group(
        self, run_date: str, run_hour: str, forecast_hour: int, idx_text: str, group: _FieldGroup
    ) -> xr.Dataset | None:
        # Fetch every field in this group's byte ranges and concatenate — a
        # cfgrib-openable multi-message file is just the concatenation of
        # each message's own bytes (GRIB2 messages are self-delimiting).
        grib_url = f"{GFS_BASE_URL}/{_run_key(run_date, run_hour, forecast_hour)}"
        chunks = []
        for (param, level_text) in group.fields:
            try:
                start, end = self._byte_range_for(idx_text, param, level_text)
            except ValueError:
                continue  # field absent at this forecast hour — skip it, not fatal (see Task 1's nullable columns)
            range_header = f"bytes={start}-{end - 1}" if end is not None else f"bytes={start}-"
            response = call_with_retries(
                lambda u=grib_url, h=range_header: self._client.get(u, headers={"Range": h})
            )
            response.raise_for_status()
            chunks.append(response.content)

        if not chunks:
            return None

        with tempfile.NamedTemporaryFile(suffix=".grib2", delete=False) as tmp:
            tmp.write(b"".join(chunks))
            tmp_path = tmp.name
        try:
            return xr.open_dataset(tmp_path, engine="cfgrib", filter_by_keys=group.filter_by_keys)
        finally:
            import os
            os.unlink(tmp_path)

    def close(self) -> None:
        if self._owns_client:
            self._client.close()
```

- [ ] **Step 7: Run discovery tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gfs_provider.py -v`
Expected: PASS (the 4 discovery tests written in Step 4).

- [ ] **Step 8: LIVE-VERIFY the remaining field groups against the real bucket (mandatory, not optional)**

This session already verified `heightAboveGround`+level=2 (TMP, RH share this typeOfLevel) end-to-end via the committed fixture. Before writing `fetch_india_grid`, actually run the following against the real bucket (a scratch script, not a committed test) to nail down the exact `filter_by_keys` for the three groups NOT yet verified:

```python
# Scratch verification — run interactively, not part of the test suite.
import httpx, tempfile, xarray as xr

client = httpx.Client(timeout=30.0)
idx = client.get("https://noaa-gfs-bdp-pds.s3.amazonaws.com/gfs.<today's discovered run>/atmos/gfs.t<HH>z.pgrb2.0p25.f000.idx").text
# Find PRMSL:mean sea level, GUST:surface, PRATE:surface, CAPE:surface, CIN:surface, TCDC:entire atmosphere
# in `idx`, fetch each byte range, open with a GUESSED filter_by_keys, and print `ds` to see what
# cfgrib actually named the typeOfLevel/level — e.g. try filter_by_keys={"typeOfLevel": "surface"}
# for the surface group, {"typeOfLevel": "meanSea"} for PRMSL, and inspect what TCDC's real
# typeOfLevel resolves to (cfgrib will tell you via the Dataset's coordinate names if your guess
# is wrong — iterate).
```

Record the confirmed `filter_by_keys` for each group directly in `fetch_india_grid`'s `_FIELD_GROUPS` list below (adjust the guessed values in Step 9's code to match whatever you actually observe — the code below is a strong starting point based on standard GFS/cfgrib naming conventions, not a guaranteed-correct final answer).

- [ ] **Step 9: Implement `fetch_india_grid` and the field-group table**

Add to `backend/app/providers/gfs.py`:

```python
_FIELD_GROUPS = [
    _FieldGroup(
        filter_by_keys={"typeOfLevel": "heightAboveGround", "level": 2},
        fields={("TMP", "2 m above ground"): "temp_2m_c", ("RH", "2 m above ground"): "relative_humidity_2m_pct"},
    ),
    _FieldGroup(
        filter_by_keys={"typeOfLevel": "heightAboveGround", "level": 10},
        fields={("UGRD", "10 m above ground"): "_u10", ("VGRD", "10 m above ground"): "_v10"},
    ),
    _FieldGroup(
        # VERIFY LIVE (Step 8) — this is the expected cfgrib mapping for "surface" fields.
        filter_by_keys={"typeOfLevel": "surface"},
        fields={
            ("GUST", "surface"): "wind_gust_kmh",
            ("PRATE", "surface"): "precip_rate_mmh",
            ("CAPE", "surface"): "cape_j_per_kg",
            ("CIN", "surface"): "cin_j_per_kg",
        },
    ),
    _FieldGroup(
        # VERIFY LIVE (Step 8).
        filter_by_keys={"typeOfLevel": "meanSea"},
        fields={("PRMSL", "mean sea level"): "_mslp_pa"},
    ),
    _FieldGroup(
        # VERIFY LIVE (Step 8) — "entire atmosphere" commonly maps to atmosphereSingleLayer in cfgrib.
        filter_by_keys={"typeOfLevel": "atmosphereSingleLayer"},
        fields={("TCDC", "entire atmosphere"): "cloud_cover_pct"},
    ),
]


def _crop_to_india(ds: xr.Dataset) -> xr.Dataset:
    return ds.sel(
        latitude=slice(_INDIA_LAT_RANGE[1], _INDIA_LAT_RANGE[0]),
        longitude=slice(_INDIA_LON_RANGE[0], _INDIA_LON_RANGE[1]),
    )


class NoaaGfsProvider:
    # ... (discover_latest_run, _fetch_idx, _byte_range_for, _fetch_field_group, close as above) ...

    def fetch_india_grid(self, run_date: str, run_hour: str, forecast_hour: int) -> list[GfsGridPointData]:
        idx_text = self._fetch_idx(run_date, run_hour, forecast_hour)
        valid_time = datetime.strptime(run_date + run_hour, "%Y%m%d%H").replace(
            tzinfo=timezone.utc
        ) + timedelta(hours=forecast_hour)

        # point_data[(lat, lon)] accumulates attribute values across every field group.
        point_data: dict[tuple[float, float], dict] = {}

        for group in _FIELD_GROUPS:
            ds = self._fetch_field_group(run_date, run_hour, forecast_hour, idx_text, group)
            if ds is None:
                continue
            ds = _crop_to_india(ds)
            grib_to_var = {param: var for var in ds.data_vars for param in [var]}  # cfgrib names vars by GRIB shortName
            for (param, _level_text), attr_name in group.fields.items():
                var_name = None
                for candidate in ds.data_vars:
                    if candidate.lower() == param.lower() or param.lower() in candidate.lower():
                        var_name = candidate
                        break
                if var_name is None:
                    continue
                values = ds[var_name].values
                lats = ds["latitude"].values
                lons = ds["longitude"].values
                for i, lat in enumerate(lats):
                    for j, lon in enumerate(lons):
                        key = (float(lat), float(lon))
                        point_data.setdefault(key, {})[attr_name] = float(values[i, j])

        results = []
        for (lat, lon), attrs in point_data.items():
            u10, v10 = attrs.pop("_u10", None), attrs.pop("_v10", None)
            wind_speed_kmh = wind_dir_deg = None
            if u10 is not None and v10 is not None:
                import math
                wind_speed_kmh = math.hypot(u10, v10) * 3.6  # m/s -> km/h
                wind_dir_deg = (math.degrees(math.atan2(-u10, -v10))) % 360  # meteorological "from" convention

            mslp_pa = attrs.pop("_mslp_pa", None)
            precip_rate_mmh = attrs.get("precip_rate_mmh")
            if precip_rate_mmh is not None:
                attrs["precip_rate_mmh"] = precip_rate_mmh * 3600  # kg/m^2/s -> mm/h (1 kg/m^2 == 1mm)
            temp_2m_c = attrs.get("temp_2m_c")
            if temp_2m_c is not None:
                attrs["temp_2m_c"] = temp_2m_c - 273.15  # K -> C

            results.append(
                GfsGridPointData(
                    run_date=run_date,
                    run_hour=run_hour,
                    forecast_hour=forecast_hour,
                    valid_time=valid_time,
                    grid_latitude=lat,
                    grid_longitude=lon,
                    temp_2m_c=attrs.get("temp_2m_c"),
                    relative_humidity_2m_pct=attrs.get("relative_humidity_2m_pct"),
                    wind_speed_10m_kmh=wind_speed_kmh,
                    wind_direction_10m_deg=wind_dir_deg,
                    wind_gust_kmh=attrs.get("wind_gust_kmh"),
                    precip_rate_mmh=attrs.get("precip_rate_mmh"),
                    cape_j_per_kg=attrs.get("cape_j_per_kg"),
                    cin_j_per_kg=attrs.get("cin_j_per_kg"),
                    cloud_cover_pct=attrs.get("cloud_cover_pct"),
                    mslp_hpa=(mslp_pa / 100.0) if mslp_pa is not None else None,
                )
            )
        return results
```

**Note on the `grib_to_var`/variable-matching logic above**: cfgrib names `xr.Dataset` variables by the GRIB short name, which is USUALLY (not always) the lowercased param (e.g. `TMP` → `t2m` or `t`, `RH` → `r2` or `r`, `UGRD` → `u10` or `u`). The substring-matching fallback in the code above is a defensive guess — **during Step 8's live verification, print `list(ds.data_vars)` for each group and hardcode the exact real variable name per group** rather than relying on fuzzy matching in the shipped code. Replace the loop above with exact `ds["t2m"]`-style access once you know the real names; leave a comment citing what you observed.

- [ ] **Step 10: Write a test proving the fixture-based parse works offline**

Add to `backend/tests/test_gfs_provider.py`:

```python
import xarray as xr


def test_committed_fixture_opens_and_yields_a_sane_temperature():
    # Confirms the checked-in fixture is genuinely valid GRIB2 and that
    # cfgrib's heightAboveGround/level=2 filter actually isolates it —
    # this is the one live-verified fact this whole task is built on.
    ds = xr.open_dataset(
        "tests/fixtures/gfs_t2m_sample.grib2",
        engine="cfgrib",
        filter_by_keys={"typeOfLevel": "heightAboveGround", "level": 2},
    )
    mumbai_temp_k = ds["t2m"].sel(latitude=19.0, longitude=73.0, method="nearest").values
    assert 260 &lt; float(mumbai_temp_k) &lt; 320  # sane Kelvin range for any real-world surface temp
```

- [ ] **Step 11: Run the full provider test file**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gfs_provider.py -v`
Expected: PASS, all tests (discovery x4 + fixture x1, minimum).

- [ ] **Step 12: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 13: One real live end-to-end smoke test (manual, report the result in your task report — not a committed automated test)**

```python
from app.providers.gfs import NoaaGfsProvider
provider = NoaaGfsProvider()
run_date, run_hour = provider.discover_latest_run()
print("Latest run:", run_date, run_hour)
points = provider.fetch_india_grid(run_date, run_hour, forecast_hour=0)
print("Got", len(points), "India grid points")
print("Sample:", points[0] if points else "NONE")
provider.close()
```

Confirm `len(points)` is in the right ballpark (should be close to 15,609, possibly fewer if some field groups' filter_by_keys guesses from Step 8 need adjustment — iterate until it's a full, sane grid with real-looking values, not zeros/NaNs).

- [ ] **Step 14: Commit**

```bash
git add backend/app/providers/nwp.py backend/app/providers/gfs.py backend/tests/test_gfs_provider.py backend/tests/fixtures/gfs_t2m_sample.grib2 backend/requirements.txt backend/requirements.lock
git commit -m "feat: add NWPProvider protocol and NoaaGfsProvider (GFS discovery, byte-range fetch, GRIB2 parsing)"
```

---

## Task 3: GFS ingestion job with run-based reconciliation

**Files:**
- Create: `backend/app/ingestion/gfs.py`
- Modify: `backend/app/main.py` (manual-trigger endpoint, mirroring `/internal/ingest/alerts`)
- Modify: `backend/app/scheduler.py`-adjacent wiring — actually just `app/main.py`'s `lifespan` (add the GFS job to the scheduler's job list)
- Modify: `backend/app/config.py` (one new setting)
- Test: `backend/tests/test_gfs_ingestion.py`

**Interfaces:**
- Consumes: `NWPProvider.discover_latest_run()` / `.fetch_india_grid(...)` (Task 2), `GfsForecastPoint` (Task 1).
- Produces: `ingest_gfs_forecast(provider: NWPProvider | None = None) -> int` (returns rows written), used by both the manual endpoint and the scheduler, exactly mirroring `ingest_alerts`/`ingest_pfz_zones`'s existing shape.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_gfs_ingestion.py`:

```python
from datetime import datetime, timezone

from sqlalchemy import insert, select

from app.db import get_engine
from app.ingestion.gfs import ingest_gfs_forecast
from app.models import GfsForecastPoint
from app.providers.nwp import GfsGridPointData


class _FakeGfsProvider:
    def __init__(self, run=("20260908", "00"), points_by_hour=None):
        self._run = run
        self._points_by_hour = points_by_hour or {}

    def discover_latest_run(self):
        return self._run

    def fetch_india_grid(self, run_date, run_hour, forecast_hour):
        return self._points_by_hour.get(forecast_hour, [])


def _point(**overrides):
    base = dict(
        run_date="20260908", run_hour="00", forecast_hour=0,
        valid_time=datetime(2026, 9, 8, tzinfo=timezone.utc),
        grid_latitude=19.0, grid_longitude=73.0,
        temp_2m_c=28.0, relative_humidity_2m_pct=70.0,
        wind_speed_10m_kmh=15.0, wind_direction_10m_deg=180.0,
        wind_gust_kmh=20.0, precip_rate_mmh=0.0,
        cape_j_per_kg=500.0, cin_j_per_kg=-50.0,
        cloud_cover_pct=40.0, mslp_hpa=1010.0,
    )
    base.update(overrides)
    return GfsGridPointData(**base)


def test_ingest_writes_rows_for_every_target_forecast_hour(clean_gfs_forecast_points):
    provider = _FakeGfsProvider(points_by_hour={0: [_point(forecast_hour=0)], 24: [_point(forecast_hour=24)]})
    count = ingest_gfs_forecast(provider, forecast_hours=[0, 24])
    assert count == 2

    with get_engine().connect() as conn:
        rows = conn.execute(select(GfsForecastPoint)).mappings().all()
    assert {r["forecast_hour"] for r in rows} == {0, 24}


def test_ingest_reconciles_away_a_prior_older_run(clean_gfs_forecast_points):
    with get_engine().begin() as conn:
        conn.execute(
            insert(GfsForecastPoint).values(
                run_date="20260907", run_hour="18", forecast_hour=0,
                valid_time=datetime(2026, 9, 7, 18, tzinfo=timezone.utc),
                grid_latitude=19.0, grid_longitude=73.0,
                fetched_at=datetime.now(timezone.utc),
            )
        )

    provider = _FakeGfsProvider(run=("20260908", "00"), points_by_hour={0: [_point(forecast_hour=0)]})
    ingest_gfs_forecast(provider, forecast_hours=[0])

    with get_engine().connect() as conn:
        rows = conn.execute(select(GfsForecastPoint)).mappings().all()
    assert {(r["run_date"], r["run_hour"]) for r in rows} == {("20260908", "00")}


def test_ingest_upserts_on_repeat_call_for_the_same_run(clean_gfs_forecast_points):
    provider = _FakeGfsProvider(points_by_hour={0: [_point(forecast_hour=0, temp_2m_c=28.0)]})
    ingest_gfs_forecast(provider, forecast_hours=[0])

    provider2 = _FakeGfsProvider(points_by_hour={0: [_point(forecast_hour=0, temp_2m_c=30.0)]})
    ingest_gfs_forecast(provider2, forecast_hours=[0])

    with get_engine().connect() as conn:
        rows = conn.execute(select(GfsForecastPoint)).mappings().all()
    assert len(rows) == 1
    assert rows[0]["temp_2m_c"] == 30.0


def test_ingest_with_no_points_for_an_hour_does_not_crash(clean_gfs_forecast_points):
    provider = _FakeGfsProvider(points_by_hour={0: []})
    count = ingest_gfs_forecast(provider, forecast_hours=[0])
    assert count == 0
```

Add a `clean_gfs_forecast_points` fixture to `backend/tests/conftest.py`, mirroring the existing `clean_pfz_zones`/`clean_weather_forecasts` fixtures exactly (same `_truncate(GfsForecastPoint)` pattern already used by every other table's fixture).

- [ ] **Step 2: Run tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gfs_ingestion.py -v`
Expected: FAIL — `app.ingestion.gfs` doesn't exist.

- [ ] **Step 3: Implement `backend/app/ingestion/gfs.py`**

```python
"""GFS ingestion: discovers the latest published model run and writes its
India-cropped grid to Postgres, reconciling away any older run's rows —
see this plan's spec for why reconciliation here is by (run_date, run_hour)
rather than by external_id presence (app/ingestion/alerts.py's pattern):
a new GFS run is a wholesale replacement of the old one, not an incremental
update to individually-identified records.
"""

import logging

from sqlalchemy import delete, or_, tuple_
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import GfsForecastPoint
from app.providers.gfs import NoaaGfsProvider
from app.providers.nwp import NWPProvider

logger = logging.getLogger(__name__)

_INGEST_GFS_LOCK_KEY = 727003
_DEFAULT_FORECAST_HOURS = [0, 24, 48, 72, 96, 120]

_MUTABLE_COLUMNS = (
    "valid_time", "temp_2m_c", "relative_humidity_2m_pct", "wind_speed_10m_kmh",
    "wind_direction_10m_deg", "wind_gust_kmh", "precip_rate_mmh", "cape_j_per_kg",
    "cin_j_per_kg", "cloud_cover_pct", "mslp_hpa", "fetched_at",
)


def ingest_gfs_forecast(
    provider: NWPProvider | None = None, forecast_hours: list[int] | None = None
) -> int:
    from datetime import datetime, timezone

    owns_provider = provider is None
    provider = provider or NoaaGfsProvider()
    forecast_hours = forecast_hours if forecast_hours is not None else _DEFAULT_FORECAST_HOURS

    try:
        run_date, run_hour = provider.discover_latest_run()
        engine = get_engine()

        with engine.begin() as conn:
            conn.execute(select_advisory_lock_stmt())

            written = 0
            for forecast_hour in forecast_hours:
                points = provider.fetch_india_grid(run_date, run_hour, forecast_hour)
                fetched_at = datetime.now(timezone.utc)
                for point in points:
                    stmt = pg_insert(GfsForecastPoint).values(
                        run_date=point.run_date, run_hour=point.run_hour,
                        forecast_hour=point.forecast_hour, valid_time=point.valid_time,
                        grid_latitude=point.grid_latitude, grid_longitude=point.grid_longitude,
                        temp_2m_c=point.temp_2m_c, relative_humidity_2m_pct=point.relative_humidity_2m_pct,
                        wind_speed_10m_kmh=point.wind_speed_10m_kmh,
                        wind_direction_10m_deg=point.wind_direction_10m_deg,
                        wind_gust_kmh=point.wind_gust_kmh, precip_rate_mmh=point.precip_rate_mmh,
                        cape_j_per_kg=point.cape_j_per_kg, cin_j_per_kg=point.cin_j_per_kg,
                        cloud_cover_pct=point.cloud_cover_pct, mslp_hpa=point.mslp_hpa,
                        fetched_at=fetched_at,
                    )
                    stmt = stmt.on_conflict_do_update(
                        index_elements=[
                            GfsForecastPoint.run_date, GfsForecastPoint.run_hour,
                            GfsForecastPoint.forecast_hour, GfsForecastPoint.grid_latitude,
                            GfsForecastPoint.grid_longitude,
                        ],
                        set_={col: getattr(stmt.excluded, col) for col in _MUTABLE_COLUMNS},
                    )
                    conn.execute(stmt)
                    written += 1

            conn.execute(
                delete(GfsForecastPoint).where(
                    or_(GfsForecastPoint.run_date != run_date, GfsForecastPoint.run_hour != run_hour)
                )
            )

        return written
    finally:
        if owns_provider and hasattr(provider, "close"):
            provider.close()


def select_advisory_lock_stmt():
    from sqlalchemy import select, func
    return select(func.pg_advisory_xact_lock(_INGEST_GFS_LOCK_KEY))
```

Note: `select_advisory_lock_stmt()` mirrors the exact `pg_advisory_xact_lock` pattern already used in `app/ingestion/alerts.py`/`marine.py` — check those files for the precise existing call shape (`conn.execute(select(func.pg_advisory_xact_lock(KEY)))` as the first statement inside the transaction) and match it exactly rather than reintroducing a slightly different variant; the constant `727003` continues this codebase's existing sequential lock-key numbering (`727001`=alerts, `727002`=marine).

- [ ] **Step 4: Run tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gfs_ingestion.py -v`
Expected: PASS.

- [ ] **Step 5: Add the manual-trigger endpoint**

In `backend/app/main.py`, add (mirroring `/internal/ingest/marine` exactly, same auth dependency):

```python
from app.ingestion.gfs import ingest_gfs_forecast

@app.post("/internal/ingest/gfs", dependencies=[Depends(verify_internal_api_key)])
def trigger_gfs_ingestion() -> dict[str, int]:
    count = ingest_gfs_forecast()
    return {"ingested": count}
```

- [ ] **Step 6: Add the scheduler job and config setting**

In `backend/app/config.py`, add: `gfs_ingestion_interval_seconds: int = 21600` (6 hours — matches GFS's own run cadence; `discover_latest_run` is cheap (a handful of HEAD requests) so checking every 6 hours won't over-fetch when nothing new has been published).

In `backend/app/main.py`'s `lifespan`, add a third job tuple to the existing `scheduler.start([...])` list:
```python
(
    "gfs",
    lambda: ingest_gfs_forecast(),
    settings.gfs_ingestion_interval_seconds,
),
```

- [ ] **Step 7: Write a test for the scheduler wiring**

Add to `backend/tests/test_scheduler_wiring.py` (follow the exact existing pattern in that file for the alerts/marine jobs — same monkeypatch-and-assert-on-scheduler.start-call-args style already used there) a test confirming a third job named `"gfs"` is included when `enable_scheduler` is true, using `settings.gfs_ingestion_interval_seconds` as its interval.

- [ ] **Step 8: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add backend/app/ingestion/gfs.py backend/app/main.py backend/app/config.py backend/tests/test_gfs_ingestion.py backend/tests/test_scheduler_wiring.py backend/tests/conftest.py
git commit -m "feat: add GFS ingestion job with run-based reconciliation, wire into scheduler"
```

---

## Task 4: `get_nwp_forecast` query service + `GET /nwp` endpoint + chat tool

**Files:**
- Create: `backend/app/nwp/__init__.py`
- Create: `backend/app/nwp/service.py`
- Modify: `backend/app/main.py`
- Modify: `backend/app/chat/tools.py`, `backend/app/chat/service.py` (system prompt)
- Test: `backend/tests/test_nwp_service.py`, `backend/tests/test_nwp_endpoint.py`, additions to `backend/tests/test_chat_tools.py`

**Interfaces:**
- Consumes: `GfsForecastPoint` rows written by Task 3.
- Produces: `get_nwp_forecast(latitude: float, longitude: float, forecast_hours: list[int] | None = None) -> list[dict]` — returns one dict per matched `(grid_point, forecast_hour)`, sorted by `forecast_hour`, excluding `id`/`grid_latitude`/`grid_longitude` (the caller asked by real-world coordinate, not grid coordinate — don't leak the snap) from the response but including `valid_time` and every field column. Raises no exception for an out-of-India-bbox coordinate — returns `[]` (mirrors this codebase's existing "no data" conventions, e.g. `geocode_place` returning `None`, `get_metar` returning `None` — here a list, so an empty list is the natural "nothing found" signal).

- [ ] **Step 1: Write the failing tests for the service**

Create `backend/tests/test_nwp_service.py`:

```python
from datetime import datetime, timezone

from sqlalchemy import insert

from app.db import get_engine
from app.models import GfsForecastPoint
from app.nwp.service import get_nwp_forecast


def _seed_point(**overrides):
    base = dict(
        run_date="20260908", run_hour="00", forecast_hour=0,
        valid_time=datetime(2026, 9, 8, tzinfo=timezone.utc),
        grid_latitude=19.0, grid_longitude=73.0,
        temp_2m_c=28.0, fetched_at=datetime.now(timezone.utc),
    )
    base.update(overrides)
    with get_engine().begin() as conn:
        conn.execute(insert(GfsForecastPoint).values(**base))


def test_snaps_an_arbitrary_coordinate_to_the_nearest_grid_point(clean_gfs_forecast_points):
    _seed_point(grid_latitude=19.0, grid_longitude=73.0, temp_2m_c=28.0)
    result = get_nwp_forecast(latitude=19.08, longitude=72.88)  # real Mumbai coordinate, nearest 0.25 grid point is (19.0, 73.0)
    assert len(result) == 1
    assert result[0]["temp_2m_c"] == 28.0


def test_out_of_india_bbox_coordinate_returns_empty(clean_gfs_forecast_points):
    _seed_point()
    result = get_nwp_forecast(latitude=51.5, longitude=-0.1)  # London
    assert result == []


def test_returns_multiple_forecast_hours_sorted(clean_gfs_forecast_points):
    _seed_point(forecast_hour=24, temp_2m_c=30.0, grid_latitude=19.0, grid_longitude=73.0)
    _seed_point(forecast_hour=0, temp_2m_c=28.0, grid_latitude=19.0, grid_longitude=73.0)
    result = get_nwp_forecast(latitude=19.0, longitude=73.0)
    assert [r["forecast_hour"] for r in result] == [0, 24]


def test_filters_to_requested_forecast_hours(clean_gfs_forecast_points):
    _seed_point(forecast_hour=0, grid_latitude=19.0, grid_longitude=73.0)
    _seed_point(forecast_hour=48, grid_latitude=19.0, grid_longitude=73.0)
    result = get_nwp_forecast(latitude=19.0, longitude=73.0, forecast_hours=[0])
    assert [r["forecast_hour"] for r in result] == [0]


def test_no_raw_payload_or_grid_coordinates_leak_into_response(clean_gfs_forecast_points):
    _seed_point()
    result = get_nwp_forecast(latitude=19.0, longitude=73.0)
    assert "grid_latitude" not in result[0]
    assert "grid_longitude" not in result[0]
    assert "id" not in result[0]
```

- [ ] **Step 2: Run tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_nwp_service.py -v`
Expected: FAIL — `app.nwp.service` doesn't exist.

- [ ] **Step 3: Implement `backend/app/nwp/service.py`**

```python
"""Query-path read of the latest ingested GFS grid (app/ingestion/gfs.py
populates this table on a scheduled cycle — see that module's docstring
for why reconciliation here works differently from every other
scheduled-broadcast source in this codebase).

Snapping an arbitrary real-world coordinate to the nearest actual 0.25-
degree grid point is exact, not an approximation: GFS's 0.25-degree grid
is perfectly regular, so round(x * 4) / 4 always lands on a real grid
node. No live provider call ever happens here — a query-time miss (the
coordinate is outside India's bounding box, or nothing has been ingested
yet) returns an empty list, never a live GFS fetch (unlike
app/weather/service.py's Open-Meteo point-lookup, GFS is not a
generously-rate-limited, arbitrary-point-queryable source — see this
plan's spec).
"""

from sqlalchemy import select

from app.db import get_engine
from app.models import GfsForecastPoint

_INDIA_LAT_RANGE = (6.0, 38.0)
_INDIA_LON_RANGE = (68.0, 98.0)

_RESPONSE_FIELDS = (
    "run_date", "run_hour", "forecast_hour", "valid_time",
    "temp_2m_c", "relative_humidity_2m_pct", "wind_speed_10m_kmh",
    "wind_direction_10m_deg", "wind_gust_kmh", "precip_rate_mmh",
    "cape_j_per_kg", "cin_j_per_kg", "cloud_cover_pct", "mslp_hpa",
)


def _snap_to_grid(value: float) -> float:
    return round(value * 4) / 4


def _to_response(row) -> dict:
    return {field: row[field] for field in _RESPONSE_FIELDS}


def get_nwp_forecast(
    latitude: float, longitude: float, forecast_hours: list[int] | None = None
) -> list[dict]:
    if not (_INDIA_LAT_RANGE[0] <= latitude <= _INDIA_LAT_RANGE[1]):
        return []
    if not (_INDIA_LON_RANGE[0] <= longitude <= _INDIA_LON_RANGE[1]):
        return []

    grid_lat = _snap_to_grid(latitude)
    grid_lon = _snap_to_grid(longitude)

    query = select(GfsForecastPoint).where(
        GfsForecastPoint.grid_latitude == grid_lat,
        GfsForecastPoint.grid_longitude == grid_lon,
    )
    if forecast_hours is not None:
        query = query.where(GfsForecastPoint.forecast_hour.in_(forecast_hours))
    query = query.order_by(GfsForecastPoint.forecast_hour)

    with get_engine().connect() as conn:
        rows = conn.execute(query).mappings().all()

    return [_to_response(row) for row in rows]
```

- [ ] **Step 4: Run tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_nwp_service.py -v`
Expected: PASS.

- [ ] **Step 5: Add the `GET /nwp` endpoint**

In `backend/app/main.py`:

```python
from app.nwp.service import get_nwp_forecast

@app.get("/nwp")
def nwp_forecast_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> list[dict]:
    return get_nwp_forecast(lat, lon)
```

Create `backend/tests/test_nwp_endpoint.py` (mirror `test_forecast_endpoint.py`'s exact pattern — seed a real row via `insert(GfsForecastPoint)`, hit the endpoint, assert on the response, plus a validation test for an out-of-range `lat`/`lon` returning 422 the same way `/weather`/`/forecast` already do).

- [ ] **Step 6: Add the chat tool**

In `backend/app/chat/tools.py`, add a `ToolSpec` named `get_nwp_forecast` (distinguish clearly in its description from the existing `get_forecast`: "Get a medium-range (up to 5-day-ahead) weather outlook from the GFS global numerical model — temperature, humidity, wind, precipitation rate, cloud cover, CAPE/CIN, and sea-level pressure at 0/24/48/72/96/120 hours ahead. Complements get_forecast (Open-Meteo, near-term) with a second, independent government-model-based source. Only covers India (6-38N, 68-98E)."), with `latitude`/`longitude` required (no `forecast_hours` param exposed to the LLM for V1 — always return all available hours, letting the LLM pick which to mention, consistent with how `list_alerts`/`list_pfz_zones` don't expose their own internal knobs either). Add the handler and register it in `_HANDLERS`. Update the system prompt in `app/chat/service.py` with a short paragraph distinguishing when to use `get_nwp_forecast` vs `get_forecast`.

Add tests to `backend/tests/test_chat_tools.py` following the exact existing pattern (update the "cover all N data sources" test to include `get_nwp_forecast` in the expected set, add an `execute_tool("get_nwp_forecast", ...)` test).

- [ ] **Step 7: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 8: Manual live verification (non-blocking is NOT appropriate here — the bucket needs no credentials, so do this for real)**

Trigger a real ingestion (`ingest_gfs_forecast()` with no injected provider) against the live bucket, then query `/nwp?lat=19.08&lon=72.88` (Mumbai) and confirm a sane 6-forecast-hour response comes back with real-looking values.

- [ ] **Step 9: Commit**

```bash
git add backend/app/nwp/ backend/app/main.py backend/app/chat/tools.py backend/app/chat/service.py backend/tests/test_nwp_service.py backend/tests/test_nwp_endpoint.py backend/tests/test_chat_tools.py
git commit -m "feat: add get_nwp_forecast query service, GET /nwp endpoint, and chat tool"
```
