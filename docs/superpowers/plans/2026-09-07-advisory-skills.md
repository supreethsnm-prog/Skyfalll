# Agriculture & Urban Advisory Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the two rules-based advisory "Skills" the V1 spec requires (§4: "Agriculture advisory" and "Urban planning / smart city monitoring") — deterministic logic over already-ingested forecast/alert data, exposed both as chat tools and as standalone query endpoints.

**Architecture:** Two new pure-Python modules (`app/skills/agriculture.py`, `app/skills/urban.py`) that call the *existing* `get_forecast`/`list_alerts` service functions (never a raw provider, never a table directly — same grounding-principle discipline as every existing chat tool) and evaluate a small, explicit, cited ruleset against the result. No LLM call happens inside a Skill — the LLM's job (per spec §2) is only to parse the user's request into a coordinate and verbalize the structured result the Skill returns. Wired in as two new chat tools (mirroring the existing six) and two new `GET` query endpoints (mirroring `/forecast`, `/geocode` — Postgres/service-only, no live provider calls at request time).

**Tech Stack:** Python, FastAPI, existing `app.forecast.service.get_forecast` and `app.warning.service.list_alerts`. No new dependency.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md

## Global Constraints

- No LLM call, no raw provider call, and no raw table query inside either Skill — only the existing `get_forecast`/`list_alerts` service functions, per spec §1's grounding principle and the pattern already established in `app/chat/tools.py`.
- Thresholds must be drawn from a real, citable classification (IMD's published rainfall-intensity and heat-wave criteria), not invented numbers — cite the source inline as a comment, exactly as the existing codebase cites Nominatim's rate-limit policy and BHASHINI's wire shapes.
- Tests never make a real network call and never depend on the current wall-clock date (forecast rows in Task 1's tests are supplied via `monkeypatch`, not seeded into Postgres with a hardcoded date — see Task 1).
- Both Skills return a JSON-serializable `dict` with no `raw_payload` key anywhere in the output (mirrors every other query-path response in this codebase).
- Follow the existing chat-tool and query-endpoint patterns exactly (see `app/chat/tools.py`, `app/main.py`'s `/forecast`/`/geocode` endpoints) — do not introduce a new response-shaping or endpoint-declaration style.

---

## Task 1: Agriculture and urban advisory Skills (rules engine)

**Files:**
- Create: `backend/app/skills/__init__.py`
- Create: `backend/app/skills/agriculture.py`
- Create: `backend/app/skills/urban.py`
- Test: `backend/tests/test_agriculture_skill.py`
- Test: `backend/tests/test_urban_skill.py`

**Interfaces:**
- Consumes: `app.forecast.service.get_forecast(latitude: float, longitude: float, days: int = 5) -> list[dict]` (each dict has keys `latitude, longitude, forecast_date, weather_code, temp_max_c, temp_min_c, precip_probability_pct, precip_sum_mm, wind_speed_max_kmh, fetched_at` — see `backend/app/forecast/service.py`). `app.warning.service.list_alerts(latitude: float | None = None, longitude: float | None = None, radius_km: float = 100.0) -> list[dict]` (each dict has keys `id, external_id, source, severity, event_type, area_description, effective_start_time, effective_end_time, warning_message, severity_color, latitude, longitude, fetched_at`, plus `distance_km` when filtered by location — see `backend/app/warning/service.py`).
- Produces: `get_agriculture_advisory(latitude: float, longitude: float, crop: str | None = None, days: int = 5) -> dict` and `get_urban_advisory(latitude: float, longitude: float, days: int = 5) -> dict`. Both are imported directly (module-level function references, so `monkeypatch.setattr(module, "get_forecast", ...)` works the same way `app/chat/tools.py` already does it) — Task 2 and Task 3 both call these two functions by name.

- [ ] **Step 1: Write `backend/app/skills/__init__.py`**

Empty file (matches `backend/app/voice/__init__.py`'s precedent — a plain package marker, no re-exports).

- [ ] **Step 2: Write the failing tests for the agriculture Skill**

Create `backend/tests/test_agriculture_skill.py`:

```python
import app.skills.agriculture as agriculture_module
from app.skills.agriculture import get_agriculture_advisory


def _forecast_day(**overrides):
    day = {
        "latitude": 19.08,
        "longitude": 72.88,
        "forecast_date": "2026-09-08",
        "weather_code": 1,
        "temp_max_c": 32.0,
        "temp_min_c": 24.0,
        "precip_probability_pct": 10.0,
        "precip_sum_mm": 0.0,
        "wind_speed_max_kmh": 15.0,
        "fetched_at": "2026-09-07T00:00:00Z",
    }
    day.update(overrides)
    return day


def _stub(monkeypatch, forecast_days, alerts=None):
    monkeypatch.setattr(agriculture_module, "get_forecast", lambda lat, lon, days=5: forecast_days)
    monkeypatch.setattr(agriculture_module, "list_alerts", lambda **kwargs: alerts or [])


def _alert(**overrides):
    alert = {
        "id": 1,
        "external_id": "a-1",
        "source": "SACHET-SDMA",
        "severity": "Moderate",
        "event_type": "Flood",
        "area_description": "Test area",
        "effective_start_time": None,
        "effective_end_time": None,
        "warning_message": None,
        "severity_color": None,
        "latitude": 19.08,
        "longitude": 72.88,
        "fetched_at": "2026-09-07T00:00:00Z",
        "distance_km": 5.0,
    }
    alert.update(overrides)
    return alert


def test_heavy_rain_triggers_advisory(monkeypatch):
    _stub(monkeypatch, [_forecast_day(precip_sum_mm=70.0)])
    result = get_agriculture_advisory(19.08, 72.88)
    assert any("Heavy rain" in a for a in result["advisories"])
    assert not any("Very heavy" in a for a in result["advisories"])


def test_very_heavy_rain_supersedes_heavy_rain_message(monkeypatch):
    _stub(monkeypatch, [_forecast_day(precip_sum_mm=150.0)])
    result = get_agriculture_advisory(19.08, 72.88)
    assert any("Very heavy rain" in a for a in result["advisories"])
    assert not any(a.startswith("Heavy rain forecast") for a in result["advisories"])


def test_severe_heat_triggers_advisory(monkeypatch):
    _stub(monkeypatch, [_forecast_day(temp_max_c=46.0)])
    result = get_agriculture_advisory(19.08, 72.88)
    assert any("Severe heat stress" in a for a in result["advisories"])


def test_moderate_heat_stress_triggers_advisory(monkeypatch):
    _stub(monkeypatch, [_forecast_day(temp_max_c=41.0)])
    result = get_agriculture_advisory(19.08, 72.88)
    assert any("Heat stress forecast" in a for a in result["advisories"])


def test_frost_risk_triggers_advisory(monkeypatch):
    _stub(monkeypatch, [_forecast_day(temp_min_c=2.0)])
    result = get_agriculture_advisory(19.08, 72.88)
    assert any("Frost risk" in a for a in result["advisories"])


def test_dry_spell_with_no_extremes_triggers_irrigation_reminder(monkeypatch):
    _stub(monkeypatch, [_forecast_day(precip_probability_pct=5.0)])
    result = get_agriculture_advisory(19.08, 72.88)
    assert any("No significant rain" in a for a in result["advisories"])


def test_crop_note_included_for_known_crop(monkeypatch):
    _stub(monkeypatch, [_forecast_day(precip_sum_mm=70.0)])
    result = get_agriculture_advisory(19.08, 72.88, crop="rice")
    assert result["crop"] == "rice"
    assert any("drainage" in a.lower() for a in result["advisories"])


def test_crop_note_lookup_is_case_insensitive(monkeypatch):
    _stub(monkeypatch, [_forecast_day()])
    result = get_agriculture_advisory(19.08, 72.88, crop="RICE")
    assert any("drainage" in a.lower() for a in result["advisories"])


def test_unknown_crop_omits_crop_note_without_error(monkeypatch):
    _stub(monkeypatch, [_forecast_day()])
    result = get_agriculture_advisory(19.08, 72.88, crop="durian")
    assert result["crop"] == "durian"
    # Should not raise, and should not fabricate a note for an unrecognized crop.


def test_relevant_alert_included_in_active_alerts(monkeypatch):
    _stub(monkeypatch, [_forecast_day()], alerts=[_alert(event_type="Flood")])
    result = get_agriculture_advisory(19.08, 72.88)
    assert [a["external_id"] for a in result["active_alerts"]] == ["a-1"]


def test_irrelevant_alert_event_type_excluded(monkeypatch):
    _stub(monkeypatch, [_forecast_day()], alerts=[_alert(event_type="Earthquake")])
    result = get_agriculture_advisory(19.08, 72.88)
    assert result["active_alerts"] == []


def test_forecast_basis_matches_input_forecast(monkeypatch):
    days = [_forecast_day(forecast_date="2026-09-08"), _forecast_day(forecast_date="2026-09-09")]
    _stub(monkeypatch, days)
    result = get_agriculture_advisory(19.08, 72.88)
    assert [d["forecast_date"] for d in result["forecast_basis"]] == ["2026-09-08", "2026-09-09"]


def test_no_raw_payload_key_anywhere_in_response(monkeypatch):
    _stub(monkeypatch, [_forecast_day()])
    result = get_agriculture_advisory(19.08, 72.88)
    assert "raw_payload" not in result
    assert all("raw_payload" not in day for day in result["forecast_basis"])
```

- [ ] **Step 3: Run the agriculture tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_agriculture_skill.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skills'`.

- [ ] **Step 4: Implement `backend/app/skills/agriculture.py`**

```python
"""Rules-based agriculture advisory Skill (spec section 4: "Agriculture
advisory" — a Skill, not a data source, since no public IMD Agromet API
exists to redistribute). Combines already-ingested forecast and alert data
through a small, explicit ruleset; the LLM verbalizes this structured
result but never invents the thresholds itself — the same grounding
principle (spec section 1) that every chat tool already enforces for raw
facts, applied here to a derived advisory instead.

Thresholds are drawn from IMD's own published classifications, not
invented — see the inline citation on each constant below.
"""

from datetime import datetime, timezone

from app.forecast.service import get_forecast
from app.warning.service import list_alerts

# IMD's 24-hour rainfall intensity classification (imd.gov.in glossary):
# light 2.5-15.5mm, moderate 15.6-64.4mm, heavy 64.5-115.5mm,
# very heavy 115.6-204.4mm, extremely heavy >204.4mm.
_HEAVY_RAIN_MM = 64.5
_VERY_HEAVY_RAIN_MM = 115.6

# IMD heat wave criteria for the plains: heat wave when max temp >= 40C,
# severe heat wave >= 45C. Used here as a field heat-stress threshold, not
# a formal IMD heat wave declaration (that also requires a
# departure-from-normal check this Skill has no baseline data for).
_HEAT_STRESS_C = 40.0
_SEVERE_HEAT_STRESS_C = 45.0

# Frost risk for standing Rabi-season crops is commonly flagged once
# overnight minimum temperature approaches 4C near ground level.
_FROST_RISK_C = 4.0

_DRY_SPELL_PRECIP_PROBABILITY_PCT = 20.0

_ALERT_RADIUS_KM = 50.0

_ALERT_KEYWORDS = ("flood", "rain", "cyclone", "storm", "heat")

# Illustrative, non-exhaustive crop-specific notes — not authoritative
# agronomic guidance, only a starting point for the advisory text.
_CROP_NOTES = {
    "rice": (
        "Standing water is tolerated, but ensure field drainage if heavy rain is "
        "forecast to prevent root rot."
    ),
    "wheat": (
        "Frost below 4C can damage standing wheat during flowering/grain-filling — "
        "consider light irrigation the evening before a forecast cold night, which "
        "raises canopy temperature."
    ),
    "cotton": (
        "Waterlogging for more than 48 hours can damage cotton root systems — "
        "prioritize drainage if heavy rain is forecast."
    ),
    "sugarcane": (
        "Tolerant of short waterlogging, but heat stress above 40C during peak "
        "growth can reduce yield — consider irrigation before hot spells."
    ),
}


def get_agriculture_advisory(
    latitude: float, longitude: float, crop: str | None = None, days: int = 5
) -> dict:
    forecast_days = get_forecast(latitude, longitude, days=days)
    alerts = list_alerts(latitude=latitude, longitude=longitude, radius_km=_ALERT_RADIUS_KM)

    advisories: list[str] = []

    very_heavy_rain_days = [d for d in forecast_days if d["precip_sum_mm"] >= _VERY_HEAVY_RAIN_MM]
    heavy_rain_days = [d for d in forecast_days if d["precip_sum_mm"] >= _HEAVY_RAIN_MM]
    if very_heavy_rain_days:
        advisories.append(
            "Very heavy rain forecast (>115.6mm/day) — hold off sowing, fertilizer, and "
            "pesticide application; ensure field drainage is clear."
        )
    elif heavy_rain_days:
        advisories.append(
            "Heavy rain forecast (>64.5mm/day) — avoid irrigation and hold off "
            "fertilizer/pesticide application until after the rain."
        )

    severe_heat_days = [d for d in forecast_days if d["temp_max_c"] >= _SEVERE_HEAT_STRESS_C]
    hot_days = [d for d in forecast_days if d["temp_max_c"] >= _HEAT_STRESS_C]
    if severe_heat_days:
        advisories.append(
            "Severe heat stress forecast (>=45C) — irrigate early morning or evening, "
            "avoid midday fieldwork."
        )
    elif hot_days:
        advisories.append(
            "Heat stress forecast (>=40C) — consider additional irrigation and avoid "
            "applying chemicals during peak afternoon heat."
        )

    frost_days = [d for d in forecast_days if d["temp_min_c"] <= _FROST_RISK_C]
    if frost_days:
        advisories.append(
            "Frost risk forecast (<=4C overnight) — light irrigation the evening before "
            "a cold night can help protect standing crops."
        )

    if not heavy_rain_days and not hot_days and forecast_days:
        dry_spell = all(
            (d["precip_probability_pct"] or 0) < _DRY_SPELL_PRECIP_PROBABILITY_PCT
            for d in forecast_days
        )
        if dry_spell:
            advisories.append(
                "No significant rain expected in the forecast window — plan irrigation "
                "accordingly."
            )

    if crop:
        note = _CROP_NOTES.get(crop.lower())
        if note:
            advisories.append(note)

    relevant_alerts = [
        a for a in alerts if any(keyword in a["event_type"].lower() for keyword in _ALERT_KEYWORDS)
    ]

    return {
        "latitude": latitude,
        "longitude": longitude,
        "crop": crop,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "advisories": advisories,
        "active_alerts": relevant_alerts,
        "forecast_basis": forecast_days,
    }
```

- [ ] **Step 5: Run the agriculture tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_agriculture_skill.py -v`
Expected: PASS, all tests.

- [ ] **Step 6: Write the failing tests for the urban Skill**

Create `backend/tests/test_urban_skill.py`:

```python
import pytest

import app.skills.urban as urban_module
from app.skills.urban import get_urban_advisory


def _forecast_day(**overrides):
    day = {
        "latitude": 19.08,
        "longitude": 72.88,
        "forecast_date": "2026-09-08",
        "weather_code": 1,
        "temp_max_c": 30.0,
        "temp_min_c": 24.0,
        "precip_probability_pct": 10.0,
        "precip_sum_mm": 0.0,
        "wind_speed_max_kmh": 15.0,
        "fetched_at": "2026-09-07T00:00:00Z",
    }
    day.update(overrides)
    return day


def _stub(monkeypatch, forecast_days, alerts=None):
    monkeypatch.setattr(urban_module, "get_forecast", lambda lat, lon, days=5: forecast_days)
    monkeypatch.setattr(urban_module, "list_alerts", lambda **kwargs: alerts or [])


@pytest.mark.parametrize(
    "precip_sum_mm,expected",
    [(10.0, "LOW"), (70.0, "MODERATE"), (150.0, "HIGH"), (250.0, "SEVERE")],
)
def test_waterlogging_risk_bands(monkeypatch, precip_sum_mm, expected):
    _stub(monkeypatch, [_forecast_day(precip_sum_mm=precip_sum_mm)])
    result = get_urban_advisory(19.08, 72.88)
    assert result["risk_summary"]["waterlogging_risk"] == expected


@pytest.mark.parametrize(
    "temp_max_c,expected",
    [(30.0, "LOW"), (37.0, "MODERATE"), (42.0, "HIGH"), (46.0, "SEVERE")],
)
def test_heat_risk_bands(monkeypatch, temp_max_c, expected):
    _stub(monkeypatch, [_forecast_day(temp_max_c=temp_max_c)])
    result = get_urban_advisory(19.08, 72.88)
    assert result["risk_summary"]["heat_risk"] == expected


@pytest.mark.parametrize("wind_speed_max_kmh,expected", [(20.0, "LOW"), (70.0, "HIGH")])
def test_wind_risk_bands(monkeypatch, wind_speed_max_kmh, expected):
    _stub(monkeypatch, [_forecast_day(wind_speed_max_kmh=wind_speed_max_kmh)])
    result = get_urban_advisory(19.08, 72.88)
    assert result["risk_summary"]["wind_risk"] == expected


def test_high_waterlogging_risk_produces_advisory(monkeypatch):
    _stub(monkeypatch, [_forecast_day(precip_sum_mm=150.0)])
    result = get_urban_advisory(19.08, 72.88)
    assert any("waterlogging risk" in a.lower() for a in result["advisories"])


def test_high_heat_risk_produces_advisory(monkeypatch):
    _stub(monkeypatch, [_forecast_day(temp_max_c=42.0)])
    result = get_urban_advisory(19.08, 72.88)
    assert any("heat risk" in a.lower() for a in result["advisories"])


def test_high_wind_risk_produces_advisory(monkeypatch):
    _stub(monkeypatch, [_forecast_day(wind_speed_max_kmh=70.0)])
    result = get_urban_advisory(19.08, 72.88)
    assert any("gale" in a.lower() for a in result["advisories"])


def test_low_risk_across_the_board_produces_no_advisories(monkeypatch):
    _stub(monkeypatch, [_forecast_day()])
    result = get_urban_advisory(19.08, 72.88)
    assert result["advisories"] == []


def test_relevant_alert_included_in_active_alerts(monkeypatch):
    alert = {
        "id": 1, "external_id": "a-1", "source": "SACHET-SDMA", "severity": "Severe",
        "event_type": "Cyclone", "area_description": "Test area", "effective_start_time": None,
        "effective_end_time": None, "warning_message": None, "severity_color": None,
        "latitude": 19.08, "longitude": 72.88, "fetched_at": "2026-09-07T00:00:00Z",
        "distance_km": 5.0,
    }
    _stub(monkeypatch, [_forecast_day()], alerts=[alert])
    result = get_urban_advisory(19.08, 72.88)
    assert [a["external_id"] for a in result["active_alerts"]] == ["a-1"]


def test_no_raw_payload_key_anywhere_in_response(monkeypatch):
    _stub(monkeypatch, [_forecast_day()])
    result = get_urban_advisory(19.08, 72.88)
    assert "raw_payload" not in result
    assert all("raw_payload" not in day for day in result["forecast_basis"])
```

- [ ] **Step 7: Run the urban tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_urban_skill.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skills.urban'`.

- [ ] **Step 8: Implement `backend/app/skills/urban.py`**

```python
"""Rules-based urban-planning advisory Skill (spec section 4: "Urban
planning / smart city monitoring" — a Skill, not a data source). Same
pattern as app/skills/agriculture.py: combines already-ingested forecast
and alert data through a deterministic ruleset, never an LLM guess.
"""

from datetime import datetime, timezone

from app.forecast.service import get_forecast
from app.warning.service import list_alerts

# IMD's 24-hour rainfall intensity classification (imd.gov.in glossary) —
# same source and thresholds as app/skills/agriculture.py.
_HEAVY_RAIN_MM = 64.5
_VERY_HEAVY_RAIN_MM = 115.6
_EXTREME_RAIN_MM = 204.4

# Heat-risk bands loosely following IMD heat wave criteria for the plains
# (heat wave >=40C, severe heat wave >=45C) plus a lower "watch" band.
_HEAT_MODERATE_C = 35.0
_HEAT_HIGH_C = 40.0
_HEAT_SEVERE_C = 45.0

# IMD's "gale" wind-speed threshold is approximately 62 km/h (34 knots).
_GALE_KMH = 62.0

_ALERT_RADIUS_KM = 50.0
_ALERT_KEYWORDS = ("flood", "rain", "cyclone", "storm", "heat")


def _waterlogging_risk(forecast_days: list[dict]) -> str:
    max_precip = max((d["precip_sum_mm"] for d in forecast_days), default=0.0)
    if max_precip >= _EXTREME_RAIN_MM:
        return "SEVERE"
    if max_precip >= _VERY_HEAVY_RAIN_MM:
        return "HIGH"
    if max_precip >= _HEAVY_RAIN_MM:
        return "MODERATE"
    return "LOW"


def _heat_risk(forecast_days: list[dict]) -> str:
    max_temp = max((d["temp_max_c"] for d in forecast_days), default=0.0)
    if max_temp >= _HEAT_SEVERE_C:
        return "SEVERE"
    if max_temp >= _HEAT_HIGH_C:
        return "HIGH"
    if max_temp >= _HEAT_MODERATE_C:
        return "MODERATE"
    return "LOW"


def _wind_risk(forecast_days: list[dict]) -> str:
    max_wind = max((d["wind_speed_max_kmh"] for d in forecast_days), default=0.0)
    return "HIGH" if max_wind >= _GALE_KMH else "LOW"


def get_urban_advisory(latitude: float, longitude: float, days: int = 5) -> dict:
    forecast_days = get_forecast(latitude, longitude, days=days)
    alerts = list_alerts(latitude=latitude, longitude=longitude, radius_km=_ALERT_RADIUS_KM)

    waterlogging_risk = _waterlogging_risk(forecast_days)
    heat_risk = _heat_risk(forecast_days)
    wind_risk = _wind_risk(forecast_days)

    advisories: list[str] = []
    if waterlogging_risk in ("HIGH", "SEVERE"):
        advisories.append(
            "High waterlogging risk — check stormwater drains and low-lying areas; "
            "avoid non-essential travel during heavy rain."
        )
    elif waterlogging_risk == "MODERATE":
        advisories.append("Moderate waterlogging risk — monitor local drainage in low-lying areas.")

    if heat_risk in ("HIGH", "SEVERE"):
        advisories.append(
            "High heat risk — activate cooling shelters/hydration points, advise outdoor "
            "workers to avoid midday exposure."
        )

    if wind_risk == "HIGH":
        advisories.append(
            "Gale-force winds forecast (>=62 km/h) — secure loose structures and hoardings, "
            "and check tree/power-line risk areas."
        )

    relevant_alerts = [
        a for a in alerts if any(keyword in a["event_type"].lower() for keyword in _ALERT_KEYWORDS)
    ]

    return {
        "latitude": latitude,
        "longitude": longitude,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "risk_summary": {
            "waterlogging_risk": waterlogging_risk,
            "heat_risk": heat_risk,
            "wind_risk": wind_risk,
        },
        "advisories": advisories,
        "active_alerts": relevant_alerts,
        "forecast_basis": forecast_days,
    }
```

- [ ] **Step 9: Run the urban tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_urban_skill.py -v`
Expected: PASS, all tests.

- [ ] **Step 10: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS (202 pre-existing + new agriculture/urban tests).

- [ ] **Step 11: Commit**

```bash
git add backend/app/skills/ backend/tests/test_agriculture_skill.py backend/tests/test_urban_skill.py
git commit -m "feat: add rules-based agriculture and urban advisory Skills"
```

---

## Task 2: Wire both Skills into the chat tool registry

**Files:**
- Modify: `backend/app/chat/tools.py`
- Modify: `backend/app/chat/service.py` (system prompt only)
- Test: `backend/tests/test_chat_tools.py`

**Interfaces:**
- Consumes: `get_agriculture_advisory(latitude, longitude, crop=None, days=5) -> dict` and `get_urban_advisory(latitude, longitude, days=5) -> dict` from Task 1 (`app.skills.agriculture`, `app.skills.urban`).
- Produces: two new entries in `TOOL_SPECS` (names `agriculture_advisory`, `urban_advisory`) and two new entries in `_HANDLERS`, consumed by Task 3's endpoint tests only indirectly (Task 3 calls the Skill functions directly, not through the chat tool layer) — no other task depends on this task's specific additions beyond the tool names existing.

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_chat_tools.py` (do not delete the existing content — add these, and update the one existing test named below):

Replace the existing `test_tool_specs_cover_all_six_data_sources` function with:

```python
def test_tool_specs_cover_all_eight_data_sources():
    names = {spec.name for spec in TOOL_SPECS}
    assert names == {
        "get_weather",
        "get_forecast",
        "geocode",
        "get_metar",
        "list_alerts",
        "list_pfz_zones",
        "agriculture_advisory",
        "urban_advisory",
    }
```

Add these new test functions to the same file:

```python
def test_execute_agriculture_advisory_returns_json(monkeypatch):
    import app.chat.tools as tools_module

    monkeypatch.setattr(
        tools_module,
        "get_agriculture_advisory",
        lambda latitude, longitude, crop=None: {"advisories": ["test advisory"], "crop": crop},
    )

    result_json = execute_tool("agriculture_advisory", {"latitude": 19.08, "longitude": 72.88})
    result = json.loads(result_json)

    assert result["advisories"] == ["test advisory"]
    assert "error" not in result


def test_execute_agriculture_advisory_passes_optional_crop(monkeypatch):
    import app.chat.tools as tools_module

    captured = {}

    def _fake(latitude, longitude, crop=None):
        captured["crop"] = crop
        return {"advisories": [], "crop": crop}

    monkeypatch.setattr(tools_module, "get_agriculture_advisory", _fake)

    execute_tool("agriculture_advisory", {"latitude": 19.08, "longitude": 72.88, "crop": "wheat"})

    assert captured["crop"] == "wheat"


def test_execute_agriculture_advisory_omits_crop_when_not_given(monkeypatch):
    import app.chat.tools as tools_module

    captured = {}

    def _fake(latitude, longitude, crop=None):
        captured["crop"] = crop
        return {"advisories": [], "crop": crop}

    monkeypatch.setattr(tools_module, "get_agriculture_advisory", _fake)

    execute_tool("agriculture_advisory", {"latitude": 19.08, "longitude": 72.88})

    assert captured["crop"] is None


def test_execute_urban_advisory_returns_json(monkeypatch):
    import app.chat.tools as tools_module

    monkeypatch.setattr(
        tools_module,
        "get_urban_advisory",
        lambda latitude, longitude: {"risk_summary": {"heat_risk": "LOW"}},
    )

    result_json = execute_tool("urban_advisory", {"latitude": 19.08, "longitude": 72.88})
    result = json.loads(result_json)

    assert result["risk_summary"]["heat_risk"] == "LOW"
    assert "error" not in result


def test_tool_specs_agriculture_advisory_declares_expected_parameters():
    spec = next(s for s in TOOL_SPECS if s.name == "agriculture_advisory")
    assert set(spec.input_schema["properties"]) == {"latitude", "longitude", "crop"}
    assert spec.input_schema["required"] == ["latitude", "longitude"]


def test_tool_specs_urban_advisory_declares_expected_parameters():
    spec = next(s for s in TOOL_SPECS if s.name == "urban_advisory")
    assert set(spec.input_schema["properties"]) == {"latitude", "longitude"}
    assert spec.input_schema["required"] == ["latitude", "longitude"]
```

- [ ] **Step 2: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v`
Expected: FAIL — `test_tool_specs_cover_all_eight_data_sources` fails (only six exist), new `agriculture_advisory`/`urban_advisory` tests fail with `AttributeError` (no such name in `app.chat.tools`) or an "Unknown tool" in-band error.

- [ ] **Step 3: Add the imports, tool specs, and handlers**

In `backend/app/chat/tools.py`, add to the existing import block:

```python
from app.skills.agriculture import get_agriculture_advisory
from app.skills.urban import get_urban_advisory
```

Append to `TOOL_SPECS` (after the existing `list_pfz_zones` entry, before the closing `]`):

```python
    ToolSpec(
        name="agriculture_advisory",
        description=(
            "Get a rules-based farming advisory (irrigation, heat-stress, frost, and "
            "heavy-rain guidance) for a specific latitude/longitude coordinate, based on "
            "the forecast and any active weather alerts nearby. Optionally pass a crop "
            "name (e.g. 'rice', 'wheat', 'cotton', 'sugarcane') for a crop-specific note."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
                "crop": {"type": "string", "description": "Optional crop name, e.g. 'rice'"},
            },
            "required": ["latitude", "longitude"],
        },
    ),
    ToolSpec(
        name="urban_advisory",
        description=(
            "Get a rules-based urban-planning advisory (waterlogging, heat, and wind risk) "
            "for a specific latitude/longitude coordinate, based on the forecast and any "
            "active weather alerts nearby."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
            "required": ["latitude", "longitude"],
        },
    ),
```

Add handler functions (near the other `_handle_*` functions):

```python
def _handle_agriculture_advisory(tool_input: dict) -> dict:
    return get_agriculture_advisory(
        latitude=tool_input["latitude"],
        longitude=tool_input["longitude"],
        crop=tool_input.get("crop"),
    )


def _handle_urban_advisory(tool_input: dict) -> dict:
    return get_urban_advisory(latitude=tool_input["latitude"], longitude=tool_input["longitude"])
```

Add both to `_HANDLERS`:

```python
    "agriculture_advisory": _handle_agriculture_advisory,
    "urban_advisory": _handle_urban_advisory,
```

- [ ] **Step 4: Update the system prompt**

In `backend/app/chat/service.py`, insert a new paragraph into `_SYSTEM_PROMPT`, after the existing paragraph that begins `"get_weather, get_forecast, list_alerts, and list_pfz_zones..."` and before the paragraph that begins `"Reply in the same language..."`:

```python
    "For farming or crop-related questions, use agriculture_advisory; for "
    "city-planning, waterlogging, or heat-risk questions, use urban_advisory. "
    "Both take coordinates, not place names — geocode first if the user named "
    "a place.\n\n"
```

- [ ] **Step 5: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v`
Expected: PASS, all tests.

- [ ] **Step 6: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/chat/tools.py backend/app/chat/service.py backend/tests/test_chat_tools.py
git commit -m "feat: wire agriculture/urban advisory Skills into the chat tool registry"
```

---

## Task 3: Standalone `/advisory/agriculture` and `/advisory/urban` endpoints

**Files:**
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_advisory_endpoints.py`

**Interfaces:** New routes only — no changes to any existing route or function signature. Consumes `get_agriculture_advisory`/`get_urban_advisory` from Task 1 directly (not through the chat tool layer).

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_advisory_endpoints.py`:

```python
from datetime import datetime, timezone

from fastapi.testclient import TestClient
from sqlalchemy import insert

from app.db import get_engine
from app.main import app
from app.models import WeatherForecast

client = TestClient(app)


def test_agriculture_advisory_endpoint_returns_structured_result(
    clean_weather_forecasts, clean_alerts_table
):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=65,
                temp_max_c=32.0, temp_min_c=25.0, precip_probability_pct=95.0,
                precip_sum_mm=80.0, wind_speed_max_kmh=20.0, raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get(
        "/advisory/agriculture", params={"lat": 19.08, "lon": 72.88, "crop": "rice", "days": 1}
    )

    assert response.status_code == 200
    body = response.json()
    assert body["crop"] == "rice"
    assert any("Heavy rain" in a for a in body["advisories"])
    assert any("drainage" in a.lower() for a in body["advisories"])
    assert "raw_payload" not in body


def test_agriculture_advisory_endpoint_validates_days_range():
    response = client.get("/advisory/agriculture", params={"lat": 19.08, "lon": 72.88, "days": 20})
    assert response.status_code == 422


def test_agriculture_advisory_endpoint_validates_latitude_range():
    response = client.get("/advisory/agriculture", params={"lat": 999, "lon": 72.88})
    assert response.status_code == 422


def test_urban_advisory_endpoint_returns_risk_summary(clean_weather_forecasts, clean_alerts_table):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=95,
                temp_max_c=46.0, temp_min_c=30.0, precip_probability_pct=95.0,
                precip_sum_mm=150.0, wind_speed_max_kmh=70.0, raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get("/advisory/urban", params={"lat": 19.08, "lon": 72.88, "days": 1})

    assert response.status_code == 200
    body = response.json()
    assert body["risk_summary"]["waterlogging_risk"] == "HIGH"
    assert body["risk_summary"]["heat_risk"] == "SEVERE"
    assert body["risk_summary"]["wind_risk"] == "HIGH"
    assert "raw_payload" not in body


def test_urban_advisory_endpoint_validates_days_range():
    response = client.get("/advisory/urban", params={"lat": 19.08, "lon": 72.88, "days": 20})
    assert response.status_code == 422
```

- [ ] **Step 2: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_advisory_endpoints.py -v`
Expected: FAIL — 404 Not Found (routes don't exist yet).

- [ ] **Step 3: Add the routes to `app/main.py`**

Add to the existing import block:

```python
from app.skills.agriculture import get_agriculture_advisory
from app.skills.urban import get_urban_advisory
```

Add near the other query-path endpoints (e.g. after `/geocode`):

```python
@app.get("/advisory/agriculture")
def agriculture_advisory_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    crop: str | None = Query(None),
    days: int = Query(5, ge=1, le=16),
) -> dict:
    return get_agriculture_advisory(lat, lon, crop=crop, days=days)


@app.get("/advisory/urban")
def urban_advisory_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    days: int = Query(5, ge=1, le=16),
) -> dict:
    return get_urban_advisory(lat, lon, days=days)
```

- [ ] **Step 4: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_advisory_endpoints.py -v`
Expected: PASS, all tests.

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/main.py backend/tests/test_advisory_endpoints.py
git commit -m "feat: add GET /advisory/agriculture and GET /advisory/urban endpoints"
```
