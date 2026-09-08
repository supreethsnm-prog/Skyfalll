from datetime import datetime, timezone

from fastapi.testclient import TestClient
from sqlalchemy import insert

from app.db import get_engine
from app.main import app
from app.models import GfsForecastPoint

client = TestClient(app)


def test_nwp_endpoint_returns_seeded_forecast(clean_gfs_forecast_points):
    with get_engine().begin() as conn:
        conn.execute(
            insert(GfsForecastPoint).values(
                run_date="20260908", run_hour="00", forecast_hour=0,
                valid_time=datetime(2026, 9, 8, tzinfo=timezone.utc),
                grid_latitude=19.0, grid_longitude=73.0,
                temp_2m_c=28.0, fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get("/nwp", params={"lat": 19.08, "lon": 72.88})

    assert response.status_code == 200
    body = response.json()
    assert body[0]["temp_2m_c"] == 28.0
    assert "grid_latitude" not in body[0]


def test_nwp_endpoint_validates_lat_range():
    response = client.get("/nwp", params={"lat": 200, "lon": 72.88})
    assert response.status_code == 422


def test_nwp_endpoint_validates_lon_range():
    response = client.get("/nwp", params={"lat": 19.08, "lon": -200})
    assert response.status_code == 422
