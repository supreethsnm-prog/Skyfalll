"""OpenMeteoArchiveProvider: daily ERA5 archive readings for any location
and date. Every field is nullable, and a missing value must never become
0 — see the module docstring on app/providers/open_meteo_archive.py.
"""

import httpx

from app.providers.open_meteo_archive import OpenMeteoArchiveProvider

# Shape confirmed live against archive-api.open-meteo.com/v1/archive.
FULL_DAY_RESPONSE = {
    "daily": {
        "time": ["2024-07-15"],
        "temperature_2m_max": [24.0],
        "temperature_2m_min": [21.4],
        "temperature_2m_mean": [22.3],
        "precipitation_sum": [20.5],
        "windspeed_10m_max": [25.8],
        "winddirection_10m_dominant": [247],
    }
}

NULL_FIELDS_RESPONSE = {
    "daily": {
        "time": ["1940-01-01"],
        "temperature_2m_max": [None],
        "temperature_2m_min": [None],
        "temperature_2m_mean": [None],
        "precipitation_sum": [None],
        "windspeed_10m_max": [None],
        "winddirection_10m_dominant": [None],
    }
}

NO_DATA_RESPONSE = {"daily": {"time": []}}


def _provider_returning(payload):
    def handler(request):
        return httpx.Response(200, json=payload)

    return OpenMeteoArchiveProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    )


def test_fetch_day_parses_a_normal_response():
    reading = _provider_returning(FULL_DAY_RESPONSE).fetch_day(
        latitude=15.36, longitude=75.12, date_str="2024-07-15"
    )

    assert reading.date == "2024-07-15"
    assert reading.temp_max_c == 24.0
    assert reading.temp_min_c == 21.4
    assert reading.temp_mean_c == 22.3
    assert reading.precip_sum_mm == 20.5
    assert reading.wind_speed_max_kmh == 25.8
    assert reading.wind_direction_dominant_deg == 247


def test_fetch_day_keeps_nulls_null():
    reading = _provider_returning(NULL_FIELDS_RESPONSE).fetch_day(
        latitude=0.0, longitude=0.0, date_str="1940-01-01"
    )

    assert reading.temp_max_c is None
    assert reading.temp_min_c is None
    assert reading.temp_mean_c is None
    assert reading.precip_sum_mm is None
    assert reading.wind_speed_max_kmh is None
    assert reading.wind_direction_dominant_deg is None


def test_fetch_day_returns_none_when_upstream_has_no_data():
    reading = _provider_returning(NO_DATA_RESPONSE).fetch_day(
        latitude=0.0, longitude=0.0, date_str="1900-01-01"
    )

    assert reading is None
