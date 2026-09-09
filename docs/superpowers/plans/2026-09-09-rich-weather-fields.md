# Rich Weather Fields Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve the weather data the Home screen currently fabricates — apparent temperature, pressure, dew point, UV index, sunrise/sunset, an hourly series, and air quality — so `demo_metrics.dart` can be deleted.

**Architecture:** Extend the existing `/weather` and `/forecast` endpoints with fields that come from the Open-Meteo call already being made, adding columns to `weather_readings` and `weather_forecasts`. The hourly series rides as a JSONB column on the weather row, since it shares that row's upstream call and TTL. Air quality is a **separate** provider, service, cache table and endpoint, because it is a different upstream host with its own freshness — mirroring the cache-with-TTL pattern already used by `app/weather/` and `app/aviation/`.

**Tech Stack:** FastAPI, SQLAlchemy Core, Alembic, Postgres, httpx, pytest.

**Spec:** No formal spec. This plan is the design record; the driving requirement is the Home screen in `frontend/weathergpt_app/lib/features/home/`, whose placeholder values are enumerated with their upstream field names in `lib/features/home/demo_metrics.dart`.

## Global Constraints

- **Additive only.** Every existing endpoint keeps its current response fields with the same names and types. The 367 existing tests must pass untouched — if one needs changing, stop and flag it rather than editing it.
- **New columns are nullable.** Rows cached before this change exist in the dev database; a `NOT NULL` column without a default breaks them and breaks the migration.
- **New response fields are nullable too.** Open-Meteo omits fields for some locations and hours. A missing value is `null`, never `0`, never an invented default. The frontend hides a tile whose value is null.
- **Mirror the existing provider shape exactly.** `OpenMeteoWeatherProvider` is the reference: an httpx client injected for tests, `params` built from a module-level field tuple, a dataclass returned, `raw_payload` retained. Do not invent a different structure for the air-quality provider.
- **No live network calls in tests.** Every provider test injects a fake `httpx.Client` or transport, as the existing provider tests do. Read `backend/tests/` for the established pattern before writing new ones.
- **No API keys.** Both Open-Meteo endpoints used here are free and unauthenticated. If a field appears to need a key, stop — it is the wrong field.
- Run tests from `backend/` with `.venv\Scripts\python -m pytest`.

## Upstream field reference (verified against Open-Meteo's docs)

| Purpose | Open-Meteo field | Request block | Endpoint |
|---|---|---|---|
| Feels like | `apparent_temperature` | `current` | forecast |
| Pressure | `pressure_msl` | `current` | forecast |
| Dew point | `dew_point_2m` | `current` | forecast |
| Hourly temp | `temperature_2m` | `hourly` | forecast |
| Hourly condition | `weather_code` | `hourly` | forecast |
| UV index | `uv_index_max` | `daily` | forecast |
| Sunrise / sunset | `sunrise`, `sunset` | `daily` | forecast |
| Air quality | `us_aqi`, `pm2_5`, `pm10` | `current` | **air-quality** (`https://air-quality-api.open-meteo.com/v1/air-quality`) |

---

## File Structure

| File | Change |
|---|---|
| `app/providers/weather.py` | Add fields to `WeatherReadingData` / `ForecastDayData` |
| `app/providers/open_meteo.py` | Request and parse the new fields |
| `app/providers/air_quality.py` | **New** — `AirQualityData` + `AirQualityProvider` protocol |
| `app/providers/open_meteo_air_quality.py` | **New** — the air-quality provider |
| `app/models.py` | New nullable columns; new `air_quality_readings` table |
| `alembic/versions/<rev>_*.py` | **New** migration(s) |
| `app/weather/service.py` | Add fields to `_RESPONSE_FIELDS` / `_MUTABLE_COLUMNS` |
| `app/forecast/service.py` | Same, for the daily fields |
| `app/air_quality/service.py` | **New** — cache-with-TTL service |
| `app/main.py` | **New** `GET /air-quality` route |

---

### Task 1: Extend the current-weather fields

**Files:**
- Modify: `app/providers/weather.py`, `app/providers/open_meteo.py`, `app/models.py`, `app/weather/service.py`
- Create: `alembic/versions/<rev>_add_rich_weather_fields.py`
- Test: `backend/tests/test_open_meteo_provider.py` (extend), `backend/tests/test_weather_service.py` (extend)

**Interfaces:**
- Produces: `/weather` gains `apparent_temperature_c`, `pressure_hpa`, `dew_point_c`, `hourly` — all nullable. `WeatherReadingData` gains the matching attributes.

Response keys are **snake_case app names, not upstream names**: `apparent_temperature` → `apparent_temperature_c`, `pressure_msl` → `pressure_hpa`, `dew_point_2m` → `dew_point_c`. This matches the existing convention (`temperature_2m` is already exposed as `temperature_c`).

`hourly` is a JSON array of `{"time": str, "temperature_c": float, "weather_code": int}`, stored in a JSONB column. Request `forecast_days=2` for the hourly block so there is always a full day ahead of the current hour; the service trims to the next 24 entries at or after `observed_at` before returning. Trimming belongs in the service, not the provider — the provider's job is to report what upstream said.

- [ ] **Step 1: Write the failing provider tests**

Extend the existing provider test file, following its established fake-transport pattern. One test proves the new fields parse; one proves absence yields `None` rather than raising — Open-Meteo genuinely omits fields for some points.

```python
def test_fetch_current_parses_rich_fields():
    payload = {  # shaped like the real response; see the existing tests
        "timezone": "Asia/Kolkata",
        "current": {
            "time": "2026-09-09T14:00",
            "temperature_2m": 29.8,
            "relative_humidity_2m": 71,
            "weather_code": 0,
            "wind_speed_10m": 2.5,
            "wind_direction_10m": 278,
            "apparent_temperature": 32.4,
            "pressure_msl": 1004.2,
            "dew_point_2m": 21.3,
        },
        "hourly": {
            "time": ["2026-09-09T14:00", "2026-09-09T15:00"],
            "temperature_2m": [29.8, 30.1],
            "weather_code": [0, 1],
        },
    }
    provider = OpenMeteoWeatherProvider(client=_fake_client(payload))
    reading = provider.fetch_current(28.61, 77.21)

    assert reading.apparent_temperature_c == 32.4
    assert reading.pressure_hpa == 1004.2
    assert reading.dew_point_c == 21.3
    assert reading.hourly[0] == {
        "time": "2026-09-09T14:00",
        "temperature_c": 29.8,
        "weather_code": 0,
    }


def test_fetch_current_tolerates_missing_rich_fields():
    # Open-Meteo omits some fields for some locations. A missing field is
    # None; it must never raise and never default to 0.
    payload = {...}  # only the original fields
    reading = OpenMeteoWeatherProvider(client=_fake_client(payload)).fetch_current(28.61, 77.21)

    assert reading.apparent_temperature_c is None
    assert reading.pressure_hpa is None
    assert reading.hourly is None
    assert reading.temperature_c == 29.8  # originals still parsed
```

- [ ] **Step 2: Run and confirm both fail**

```powershell
.venv\Scripts\python -m pytest tests/test_open_meteo_provider.py -v
```

- [ ] **Step 3: Implement provider + dataclass**

Add the fields to `_CURRENT_FIELDS`, add an `_HOURLY_FIELDS` tuple and a `"hourly"` param, add `"forecast_days": 2`. Parse with `.get()`, not `[]`, so absence yields `None`.

- [ ] **Step 4: Add the model columns and migration**

New nullable columns on `weather_readings`: `apparent_temperature_c` (Float), `pressure_hpa` (Float), `dew_point_c` (Float), `hourly` (JSONB). Generate with `alembic revision --autogenerate`, then **read the generated file** and confirm it only adds these columns — autogenerate sometimes emits spurious drops from type-comparison noise.

- [ ] **Step 5: Extend the service**

Add the four names to both `_RESPONSE_FIELDS` and `_MUTABLE_COLUMNS`. Add the hourly trim: next 24 entries at or after `observed_at`. Test that a cached row round-trips the new fields, and that the trim returns 24 entries from a 48-entry series.

- [ ] **Step 6: Full verification and commit**

```powershell
.venv\Scripts\python -m pytest
```

All previously-existing tests must still pass, untouched.

```bash
git add backend/
git commit -m "feat: serve apparent temperature, pressure, dew point and hourly series"
```

---

### Task 2: Extend the forecast fields

**Files:**
- Modify: `app/providers/weather.py`, `app/providers/open_meteo.py`, `app/models.py`, `app/forecast/service.py`, plus a migration
- Test: extend the provider and forecast-service tests

**Interfaces:**
- Produces: each `/forecast` day gains `uv_index_max`, `sunrise`, `sunset` — all nullable.

`sunrise`/`sunset` arrive as ISO datetime strings and are stored and returned as strings, exactly as `forecast_date` and `observed_at` already are. Do not parse them into `datetime` — the existing code deliberately keeps upstream time strings verbatim, and the frontend formats for display.

- [ ] **Step 1: Write the failing tests** — one proving the fields parse, one proving absence yields `None`.
- [ ] **Step 2: Run and confirm they fail**
- [ ] **Step 3: Add `uv_index_max`, `sunrise`, `sunset` to `_DAILY_FIELDS` and `ForecastDayData`**
- [ ] **Step 4: Add nullable columns to `weather_forecasts` + migration**
- [ ] **Step 5: Add to `forecast/service.py`'s response and mutable-column tuples**
- [ ] **Step 6: Full suite, then commit** — `feat: serve UV index and sunrise/sunset on the forecast`

---

### Task 3: Air-quality provider, service and endpoint

**Files:**
- Create: `app/providers/air_quality.py`, `app/providers/open_meteo_air_quality.py`, `app/air_quality/__init__.py`, `app/air_quality/service.py`
- Modify: `app/models.py`, `app/main.py`, plus a migration
- Test: `backend/tests/test_open_meteo_air_quality_provider.py`, `backend/tests/test_air_quality_service.py`, plus an endpoint test in the existing endpoint test file

**Interfaces:**
- Produces: `GET /air-quality?lat=&lon=` → `{latitude, longitude, us_aqi, pm2_5, pm10, observed_at, fetched_at}`, every pollutant field nullable.

Read `app/weather/service.py` and `app/aviation/service.py` first and follow their structure: check Postgres, return the row if inside the freshness window, otherwise call the provider and upsert. Use a **60-minute** freshness window — air quality moves far more slowly than weather's 20 minutes, and this endpoint is more heavily rate-limited.

Base URL `https://air-quality-api.open-meteo.com/v1/air-quality`, current fields `us_aqi,pm2_5,pm10`. Same free service, no key.

- [ ] **Step 1: Write the failing provider test** — parses `us_aqi`/`pm2_5`/`pm10`; missing fields yield `None`; a non-200 raises the same error type the existing weather provider raises (check what that is rather than assuming).
- [ ] **Step 2: Run and confirm it fails**
- [ ] **Step 3: Implement the provider and its protocol**
- [ ] **Step 4: Add the `air_quality_readings` table + migration** — same unique-constraint shape as `weather_readings` (`latitude`, `longitude`), same `raw_payload` JSONB and `fetched_at` columns.
- [ ] **Step 5: Write the failing service test, then implement the service** — a cache hit inside the window does not call the provider; a stale row does; the provider result is upserted. The existing weather-service tests show how to fake the provider.
- [ ] **Step 6: Add the route to `app/main.py`** — mirror `get_weather_endpoint`'s signature and validation exactly.
- [ ] **Step 7: Full suite, then commit** — `feat: add air-quality endpoint backed by Open-Meteo`

---

### Task 4: Bind the Home screen to real data

**Files:**
- Delete: `frontend/weathergpt_app/lib/features/home/demo_metrics.dart`
- Modify: `lib/data/weather_api.dart`, `lib/features/home/home_controller.dart`, `lib/features/home/widgets/detail_tiles.dart`, `test/golden/home_golden_test.dart`, `test/support/fake_apis.dart`
- Create: `lib/data/air_quality_api.dart`, `test/data/air_quality_api_test.dart`
- Test: extend `test/data/weather_api_test.dart`

**Interfaces:**
- Consumes: everything Tasks 1-3 produce.

`CurrentWeather` gains the nullable fields and an `hourly` list; `ForecastDay` gains `uvIndexMax`, `sunrise`, `sunset`. New `AirQualityApi` mirroring `WeatherApi`'s shape exactly. `HomeController` fetches air quality as a fourth concurrent call in the existing `Future.wait`, and `HomeLoaded` carries it.

**Every tile must hide itself when its value is null**, rather than rendering a dash or a zero. Google Weather omits tiles it has no data for and so must this — a "0" UV index reads as a real measurement.

Delete `demo_metrics.dart` outright. Do not keep it as a fallback: a silent fetch failure must surface as an error, never as invented numbers presented as readings.

- [ ] **Step 1: Write failing parser tests** for the new nullable fields, including a payload where they are all absent.
- [ ] **Step 2: Run and confirm they fail**
- [ ] **Step 3: Extend the models and add `AirQualityApi`**
- [ ] **Step 4: Extend `HomeController` and `HomeLoaded`** — a failing air-quality call must NOT fail the whole screen; catch it and leave air quality null, since weather is the primary content. This is a deliberate exception to the controller's existing all-or-nothing rule; comment it as such.
- [ ] **Step 5: Bind the tiles, deleting `demo_metrics.dart`**
- [ ] **Step 6: Regenerate goldens and verify determinism**

```powershell
flutter test --update-goldens test\golden\home_golden_test.dart
flutter test test\golden\home_golden_test.dart
```

- [ ] **Step 7: Full `flutter analyze` + `flutter test`, then commit** — `feat: bind Home to real weather and air-quality data`

---

## Verification

Backend: full pytest suite green with every pre-existing test unmodified; migrations apply cleanly to the dev database that already holds cached rows. Frontend: `flutter analyze` clean, `flutter test` passing, goldens regenerated and deterministic. The controller inspects the regenerated Home PNGs by eye — the tiles must show real values, and any tile without data must be absent rather than zeroed.
