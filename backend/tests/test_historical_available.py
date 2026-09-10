"""`/historical/available` — what the historical dataset actually covers.

`/historical` matches an exact location name AND date against a small,
fixed seed matrix. Without a discovery endpoint a client can only guess
and collect 404s, which made the whole feature undiscoverable from the UI.
"""

from datetime import datetime, timezone

from fastapi.testclient import TestClient
from sqlalchemy import insert

from app.db import get_engine
from app.history.service import list_available_history
from app.main import app
from app.models import HistoricalWeatherReading

client = TestClient(app)


def _seed(location: str, date: str, lat: float = 18.52, lon: float = 73.86):
    with get_engine().begin() as conn:
        conn.execute(
            insert(HistoricalWeatherReading).values(
                location_name=location,
                observation_date=date,
                latitude=lat,
                longitude=lon,
                temp_2m_c=25.0,
                dewpoint_2m_c=22.0,
                precip_mm=0.2,
                wind_speed_10m_kmh=8.0,
                wind_direction_10m_deg=260.0,
                mslp_hpa=1001.0,
                fetched_at=datetime.now(timezone.utc),
            )
        )


def test_reports_nothing_when_the_table_is_empty(clean_historical_weather_readings):
    # The common state in development: the test suite truncates this table,
    # and a real seed is expensive. An empty list is the honest answer.
    assert list_available_history() == []


def test_groups_dates_under_their_location(clean_historical_weather_readings):
    _seed("Pune", "2024-07-15")
    _seed("Pune", "2023-07-15")
    _seed("New Delhi", "2024-01-15", lat=28.61, lon=77.21)

    available = list_available_history()

    by_name = {entry["location_name"]: entry for entry in available}
    assert set(by_name) == {"Pune", "New Delhi"}
    assert sorted(by_name["Pune"]["dates"]) == ["2023-07-15", "2024-07-15"]
    assert by_name["New Delhi"]["dates"] == ["2024-01-15"]


def test_carries_coordinates_so_a_client_can_map_a_place(
    clean_historical_weather_readings,
):
    _seed("New Delhi", "2024-01-15", lat=28.61, lon=77.21)

    entry = list_available_history()[0]

    assert entry["latitude"] == 28.61
    assert entry["longitude"] == 77.21


def test_dates_are_newest_first(clean_historical_weather_readings):
    # A UI offering dates wants the most recent one first.
    _seed("Pune", "2023-07-15")
    _seed("Pune", "2024-07-15")
    _seed("Pune", "2024-01-15")

    assert list_available_history()[0]["dates"] == [
        "2024-07-15",
        "2024-01-15",
        "2023-07-15",
    ]


def test_endpoint_returns_the_coverage(clean_historical_weather_readings):
    _seed("Pune", "2024-07-15")

    response = client.get("/historical/available")

    assert response.status_code == 200
    body = response.json()
    assert body[0]["location_name"] == "Pune"
    assert body[0]["dates"] == ["2024-07-15"]


def test_available_route_is_not_shadowed_by_the_lookup_route(
    clean_historical_weather_readings,
):
    # /historical requires `location` and `date` query params. If the
    # routes were declared the other way round, /historical/available
    # would 404 or 422 instead of listing coverage.
    response = client.get("/historical/available")

    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_every_advertised_pair_actually_resolves(
    clean_historical_weather_readings,
):
    # The point of the endpoint: anything it advertises must be fetchable.
    _seed("Pune", "2024-07-15")
    _seed("Pune", "2023-07-15")
    _seed("New Delhi", "2024-01-15", lat=28.61, lon=77.21)

    for entry in client.get("/historical/available").json():
        for date in entry["dates"]:
            lookup = client.get(
                "/historical",
                params={"location": entry["location_name"], "date": date},
            )
            assert lookup.status_code == 200, (entry["location_name"], date)
