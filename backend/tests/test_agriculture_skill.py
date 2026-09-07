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
