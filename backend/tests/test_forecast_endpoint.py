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
