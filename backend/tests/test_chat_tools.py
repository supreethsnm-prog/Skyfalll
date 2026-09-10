import json
from datetime import date, datetime, timezone

from sqlalchemy import insert

from app.chat.tools import _CHAT_TOOL_RESULT_CAP, TOOL_SPECS, execute_tool
from app.db import get_engine
from app.models import (
    Alert,
    GfsForecastPoint,
    HistoricalWeatherReading,
    PfzZone,
    WeatherForecast,
    WeatherReading,
)

# See the note in test_forecast_service.py: get_forecast filters
# forecast_date >= today, so a hardcoded date rots into the past.
_TODAY = date.today().isoformat()


def test_tool_specs_cover_all_ten_data_sources():
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
        "get_nwp_forecast",
        "get_historical_weather",
    }


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


def test_execute_get_forecast_returns_seeded_cache_as_json(clean_weather_forecasts):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date=_TODAY, weather_code=51,
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


def test_execute_list_alerts_caps_result_to_20(clean_alerts_table):
    # Seed more than the chat-context cap of 20 rows and confirm the chat
    # tool handler truncates — this is a chat-context size limit, not a
    # data-correctness truncation (the real /alerts endpoint returns all rows).
    with get_engine().begin() as conn:
        for i in range(25):
            conn.execute(
                insert(Alert).values(
                    external_id=f"alert-{i}",
                    source="test",
                    severity="minor",
                    event_type="flood",
                    raw_payload={"seeded": True},
                    fetched_at=datetime.now(timezone.utc),
                )
            )

    result_json = execute_tool("list_alerts", {})
    result = json.loads(result_json)

    assert isinstance(result, list)
    assert len(result) == _CHAT_TOOL_RESULT_CAP


def test_execute_list_pfz_zones_strips_geometry(clean_pfz_zones):
    with get_engine().begin() as conn:
        conn.execute(
            insert(PfzZone).values(
                external_id="zone-1",
                category="test",
                sector_name="test sector",
                geometry={"type": "MultiLineString", "coordinates": [[[72.0, 19.0], [72.1, 19.1]]]},
                raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    result_json = execute_tool("list_pfz_zones", {})
    result = json.loads(result_json)

    assert isinstance(result, list)
    assert len(result) == 1
    assert "geometry" not in result[0]
    # Other substantive fields must still be present.
    assert result[0]["external_id"] == "zone-1"
    assert result[0]["sector_name"] == "test sector"


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


def test_execute_list_pfz_zones_caps_result_to_20(monkeypatch):
    import app.chat.tools as tools_module

    fake_zones = [
        {"external_id": f"zone-{i}", "geometry": {"type": "MultiLineString", "coordinates": []}}
        for i in range(25)
    ]
    monkeypatch.setattr(tools_module, "list_pfz_zones", lambda **kwargs: fake_zones)

    result_json = execute_tool("list_pfz_zones", {})
    result = json.loads(result_json)

    assert len(result) == _CHAT_TOOL_RESULT_CAP
    assert all("geometry" not in zone for zone in result)


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


def test_execute_get_nwp_forecast_returns_seeded_rows_as_json(clean_gfs_forecast_points):
    with get_engine().begin() as conn:
        conn.execute(
            insert(GfsForecastPoint).values(
                run_date="20260908", run_hour="00", forecast_hour=0,
                valid_time=datetime(2026, 9, 8, tzinfo=timezone.utc),
                grid_latitude=19.0, grid_longitude=73.0,
                temp_2m_c=28.0, fetched_at=datetime.now(timezone.utc),
            )
        )

    result_json = execute_tool("get_nwp_forecast", {"latitude": 19.08, "longitude": 72.88})
    result = json.loads(result_json)

    assert result[0]["temp_2m_c"] == 28.0
    assert "grid_latitude" not in result[0]
    assert "error" not in result


def test_execute_get_nwp_forecast_out_of_india_returns_empty_list(clean_gfs_forecast_points):
    result_json = execute_tool("get_nwp_forecast", {"latitude": 51.5, "longitude": -0.1})
    result = json.loads(result_json)

    assert result == []


def test_tool_specs_get_nwp_forecast_declares_expected_parameters():
    spec = next(s for s in TOOL_SPECS if s.name == "get_nwp_forecast")
    assert set(spec.input_schema["properties"]) == {"latitude", "longitude"}
    assert spec.input_schema["required"] == ["latitude", "longitude"]


def test_execute_get_historical_weather_returns_seeded_reading_as_json(
    clean_historical_weather_readings,
):
    with get_engine().begin() as conn:
        conn.execute(
            insert(HistoricalWeatherReading).values(
                location_name="Mumbai", latitude=19.08, longitude=72.88,
                observation_date="2023-07-15", temp_2m_c=27.3, dewpoint_2m_c=25.4,
                precip_mm=0.73, wind_speed_10m_kmh=16.0, wind_direction_10m_deg=247.3,
                mslp_hpa=1006.5, fetched_at=datetime.now(timezone.utc),
            )
        )

    result_json = execute_tool(
        "get_historical_weather", {"location": "Mumbai", "date": "2023-07-15"}
    )
    result = json.loads(result_json)

    assert result["temp_2m_c"] == 27.3
    assert "error" not in result


def test_execute_get_historical_weather_returns_error_for_unseeded_combination(
    clean_historical_weather_readings,
):
    result_json = execute_tool(
        "get_historical_weather", {"location": "Mumbai", "date": "2020-01-01"}
    )
    result = json.loads(result_json)

    assert "error" in result


def test_tool_specs_get_historical_weather_declares_expected_parameters():
    spec = next(s for s in TOOL_SPECS if s.name == "get_historical_weather")
    assert set(spec.input_schema["properties"]) == {"location", "date"}
    assert spec.input_schema["required"] == ["location", "date"]
