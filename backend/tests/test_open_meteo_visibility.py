"""Visibility, and the sub-hour timestamp mismatch it exposed.

Open-Meteo's `current` block reports at 15-minute granularity
("2026-09-09T20:45") while its `hourly` block is always on the hour
("2026-09-09T20:00"). An exact-equality lookup between the two therefore
never matches, and visibility came back None for every real request while
passing any test whose fixture happened to use on-the-hour times.

These tests use OFF-the-hour current times on purpose. A fixture with
"...T20:00" would pass against the broken implementation.
"""

import httpx

from app.providers.open_meteo import OpenMeteoWeatherProvider

# current.time is 20:45; the hourly series is on the hour.
OFF_HOUR_RESPONSE = {
    "timezone": "Asia/Kolkata",
    "current": {
        "time": "2026-09-09T20:45",
        "temperature_2m": 26.8,
        "relative_humidity_2m": 64,
        "weather_code": 2,
        "wind_speed_10m": 7.1,
        "wind_direction_10m": 240,
    },
    "hourly": {
        "time": ["2026-09-09T19:00", "2026-09-09T20:00", "2026-09-09T21:00"],
        "temperature_2m": [27.4, 26.8, 26.1],
        "weather_code": [1, 2, 2],
        # Metres upstream.
        "visibility": [24140.0, 16090.0, 12070.0],
    },
}


def _provider_returning(payload):
    def handler(request):
        return httpx.Response(200, json=payload)

    return OpenMeteoWeatherProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    )


def test_visibility_matches_the_containing_hour_not_an_exact_timestamp():
    reading = _provider_returning(OFF_HOUR_RESPONSE).fetch_current(12.97, 77.59)

    # 20:45 falls in the 20:00 hour -> 16090 m.
    assert reading.visibility_km == 16.09


def test_visibility_is_converted_from_metres_to_km():
    reading = _provider_returning(OFF_HOUR_RESPONSE).fetch_current(12.97, 77.59)

    # 16090 m is ~10 miles; a raw-metres bug would show 16090 km.
    assert 1 < reading.visibility_km < 100


def test_visibility_is_none_when_the_field_is_absent():
    payload = {
        "timezone": "Asia/Kolkata",
        "current": {
            "time": "2026-09-09T20:45",
            "temperature_2m": 26.8,
            "relative_humidity_2m": 64,
            "weather_code": 2,
            "wind_speed_10m": 7.1,
            "wind_direction_10m": 240,
        },
        "hourly": {
            "time": ["2026-09-09T20:00"],
            "temperature_2m": [26.8],
            "weather_code": [2],
        },
    }

    reading = _provider_returning(payload).fetch_current(12.97, 77.59)

    assert reading.visibility_km is None
    assert reading.temperature_c == 26.8


def test_visibility_is_none_when_the_hour_is_missing_from_the_series():
    payload = {
        "timezone": "Asia/Kolkata",
        "current": {
            "time": "2026-09-09T23:45",
            "temperature_2m": 26.8,
            "relative_humidity_2m": 64,
            "weather_code": 2,
            "wind_speed_10m": 7.1,
            "wind_direction_10m": 240,
        },
        "hourly": {
            "time": ["2026-09-09T19:00"],
            "temperature_2m": [27.4],
            "weather_code": [1],
            "visibility": [24140.0],
        },
    }

    reading = _provider_returning(payload).fetch_current(12.97, 77.59)

    assert reading.visibility_km is None
