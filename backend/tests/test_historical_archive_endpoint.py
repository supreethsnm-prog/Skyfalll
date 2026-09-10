"""GET /historical/archive: live Open-Meteo archive reading for any
location/date, plus the same-calendar-date-previous-year comparison
reading in the same response.
"""

from fastapi.testclient import TestClient

from app.main import app
from app.providers.open_meteo_archive import ArchiveDayData, OpenMeteoArchiveProvider

client = TestClient(app)


def test_archive_endpoint_returns_reading_and_previous_year(monkeypatch):
    readings = {
        "2024-07-15": ArchiveDayData(
            date="2024-07-15",
            temp_max_c=24.0,
            temp_min_c=21.4,
            temp_mean_c=22.3,
            precip_sum_mm=20.5,
            wind_speed_max_kmh=25.8,
            wind_direction_dominant_deg=247,
        ),
        "2023-07-15": ArchiveDayData(
            date="2023-07-15",
            temp_max_c=23.1,
            temp_min_c=20.0,
            temp_mean_c=21.5,
            precip_sum_mm=5.0,
            wind_speed_max_kmh=18.0,
            wind_direction_dominant_deg=200,
        ),
    }

    def fake_fetch_day(self, latitude, longitude, date_str):
        return readings[date_str]

    monkeypatch.setattr(OpenMeteoArchiveProvider, "fetch_day", fake_fetch_day)

    response = client.get(
        "/historical/archive",
        params={"lat": 15.36, "lon": 75.12, "date": "2024-07-15", "name": "Hubballi"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["location_name"] == "Hubballi"
    assert body["reading"]["temp_max_c"] == 24.0
    assert body["previous_year_reading"]["date"] == "2023-07-15"
    assert body["previous_year_reading"]["temp_max_c"] == 23.1


def test_archive_endpoint_keeps_nulls_null_and_404s_on_no_data(monkeypatch):
    def fake_fetch_day(self, latitude, longitude, date_str):
        if date_str == "1900-01-01":
            return None
        return ArchiveDayData(
            date=date_str,
            temp_max_c=None,
            temp_min_c=None,
            temp_mean_c=None,
            precip_sum_mm=None,
            wind_speed_max_kmh=None,
            wind_direction_dominant_deg=None,
        )

    monkeypatch.setattr(OpenMeteoArchiveProvider, "fetch_day", fake_fetch_day)

    response = client.get(
        "/historical/archive",
        params={"lat": 0.0, "lon": 0.0, "date": "1900-01-01"},
    )
    assert response.status_code == 404
