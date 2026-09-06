from datetime import datetime, timezone

from fastapi.testclient import TestClient
from sqlalchemy import insert

from app.db import get_engine
from app.main import app
from app.models import MetarReading

client = TestClient(app)


def test_metar_endpoint_returns_cached_reading(clean_metar_readings):
    with get_engine().begin() as conn:
        conn.execute(
            insert(MetarReading).values(
                icao_id="VABB",
                raw_metar="METAR VABB 060900Z 28012KT 3000 BR BKN090 30/25 Q1011 NOSIG",
                observed_at="2026-09-06T09:00:00.000Z",
                temperature_c=30.0,
                dewpoint_c=25.0,
                wind_dir_deg=280.0,
                wind_speed_kt=12.0,
                visibility_sm=1.86,
                flight_category="IFR",
                station_name="Mumbai/Shivaji Intl, MM, IN",
                latitude=19.1,
                longitude=72.859,
                raw_payload={"icaoId": "VABB"},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    response = client.get("/metar", params={"icao": "VABB"})

    assert response.status_code == 200
    body = response.json()
    assert body["temperature_c"] == 30.0
    assert "raw_payload" not in body


def test_metar_endpoint_returns_404_when_not_found(monkeypatch):
    monkeypatch.setattr("app.main.get_metar", lambda icao: None)

    response = client.get("/metar", params={"icao": "ZZZZ"})

    assert response.status_code == 404


def test_metar_endpoint_rejects_wrong_length_icao_code():
    response = client.get("/metar", params={"icao": "AB"})

    assert response.status_code == 422
