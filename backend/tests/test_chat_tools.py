import json
from datetime import datetime, timezone

from sqlalchemy import insert

from app.chat.tools import TOOL_SPECS, execute_tool
from app.db import get_engine
from app.models import WeatherReading


def test_tool_specs_cover_all_five_data_sources():
    names = {spec.name for spec in TOOL_SPECS}
    assert names == {"get_weather", "geocode", "get_metar", "list_alerts", "list_pfz_zones"}


def test_execute_get_weather_returns_seeded_cache_as_json(clean_weather_readings):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=28.0,
                humidity_pct=70,
                weather_code=1,
                wind_speed_kmh=10.0,
                wind_direction_deg=180,
                observed_at="2026-09-06T12:00",
                timezone="Asia/Kolkata",
                raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    result_json = execute_tool("get_weather", {"latitude": 19.08, "longitude": 72.88})
    result = json.loads(result_json)

    assert result["temperature_c"] == 28.0
    assert "raw_payload" not in result
    assert "error" not in result


def test_execute_geocode_reports_not_found_as_in_band_error(monkeypatch):
    # geocode_place would otherwise hit the real network on a cache miss
    # with no injected provider seam (unlike get_weather/get_metar, this
    # test can't seed a Postgres cache row to avoid it — geocoding's
    # cache key is a normalized query string, not a coordinate, and
    # there is no "not found" row to seed by design, see
    # app/geocoding/service.py's docstring). Patch the name app/chat/tools.py
    # imported instead.
    import app.chat.tools as tools_module

    monkeypatch.setattr(tools_module, "geocode_place", lambda query: None)

    result_json = execute_tool("geocode", {"query": "nonexistent place"})
    result = json.loads(result_json)

    assert "error" in result


def test_execute_get_weather_live_fetch_failure_returns_in_band_error(monkeypatch):
    # Simulates a live provider failure (e.g. httpx.HTTPStatusError,
    # httpx.ConnectError) on a cache miss, as opposed to malformed input.
    # execute_tool must convert this to an in-band {"error": ...} result
    # rather than letting it propagate and crash the chat turn.
    import app.chat.tools as tools_module

    def _boom(latitude, longitude):
        raise RuntimeError("upstream weather provider unreachable")

    monkeypatch.setattr(tools_module, "get_weather", _boom)

    result_json = execute_tool("get_weather", {"latitude": 19.08, "longitude": 72.88})
    result = json.loads(result_json)

    assert "error" in result


def test_execute_get_metar_missing_icao_returns_in_band_error():
    result_json = execute_tool("get_metar", {})
    result = json.loads(result_json)

    assert "error" in result


def test_execute_unknown_tool_returns_in_band_error():
    result_json = execute_tool("not_a_real_tool", {})
    result = json.loads(result_json)

    assert "error" in result
    assert "not_a_real_tool" in result["error"]


def test_execute_list_alerts_returns_json_list(clean_alerts_table):
    result_json = execute_tool("list_alerts", {})
    result = json.loads(result_json)

    assert isinstance(result, list)


def test_execute_list_pfz_zones_returns_json_list(clean_pfz_zones):
    result_json = execute_tool("list_pfz_zones", {})
    result = json.loads(result_json)

    assert isinstance(result, list)
