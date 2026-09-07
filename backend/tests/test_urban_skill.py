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
