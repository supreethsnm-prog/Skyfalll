from datetime import date, datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlalchemy import insert

from app.db import get_engine
from app.main import app
from app.models import WeatherForecast

client = TestClient(app)


def _future_forecast_date() -> str:
    """Always ahead of ``date.today()``, which the real ``get_forecast`` filters
    on — a hardcoded date would eventually stop matching and let the test fall
    through to a live network call."""
    return (date.today() + timedelta(days=1)).isoformat()


def test_agriculture_advisory_endpoint_returns_structured_result(
    clean_weather_forecasts, clean_alerts_table
):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date=_future_forecast_date(),
                weather_code=65,
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
                latitude=19.08, longitude=72.88, forecast_date=_future_forecast_date(),
                weather_code=95,
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
