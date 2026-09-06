from datetime import datetime, timezone

from sqlalchemy import insert
from fastapi.testclient import TestClient

from app.db import get_engine
from app.main import app
from app.models import WeatherReading

client = TestClient(app)


def test_weather_endpoint_returns_cached_reading(clean_weather_readings):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=28.1,
                humidity_pct=79,
                weather_code=51,
                wind_speed_kmh=9.7,
                wind_direction_deg=255,
                observed_at="2026-09-06T12:00",
                timezone="Asia/Kolkata",
                raw_payload={"cached": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get("/weather", params={"lat": 19.08, "lon": 72.88})

    assert response.status_code == 200
    body = response.json()
    assert body["temperature_c"] == 28.1
    assert "raw_payload" not in body
