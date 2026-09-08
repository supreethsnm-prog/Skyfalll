from datetime import datetime, timezone

from fastapi.testclient import TestClient
from sqlalchemy import insert

from app.db import get_engine
from app.main import app
from app.models import HistoricalWeatherReading

client = TestClient(app)


def test_historical_endpoint_returns_seeded_reading(clean_historical_weather_readings):
    with get_engine().begin() as conn:
        conn.execute(
            insert(HistoricalWeatherReading).values(
                location_name="Mumbai", latitude=19.08, longitude=72.88,
                observation_date="2023-07-15", temp_2m_c=27.3, dewpoint_2m_c=25.4,
                precip_mm=0.73, wind_speed_10m_kmh=16.0, wind_direction_10m_deg=247.3,
                mslp_hpa=1006.5, fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get("/historical", params={"location": "Mumbai", "date": "2023-07-15"})

    assert response.status_code == 200
    body = response.json()
    assert body["temp_2m_c"] == 27.3
    assert body["precip_mm"] == 0.73
    assert "id" not in body


def test_historical_endpoint_returns_404_with_helpful_message_for_unseeded_combination(
    clean_historical_weather_readings,
):
    response = client.get("/historical", params={"location": "Mumbai", "date": "2020-01-01"})

    assert response.status_code == 404
    detail = response.json()["detail"]
    assert "Mumbai" in detail
    assert "2020-01-01" in detail
