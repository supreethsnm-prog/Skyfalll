"""Rich Open-Meteo fields: apparent temperature, pressure, dew point, the
hourly series, UV index and sunrise/sunset.

Kept separate from test_open_meteo_provider.py so that file — which covers
the original contract — stays untouched by this change.

Every field here is nullable. Open-Meteo omits them for some points, and a
missing value must never become 0: a "0" UV index or "0 hPa" reads as a
real measurement on the Home screen rather than as absent data.
"""

import httpx

from app.providers.open_meteo import OpenMeteoWeatherProvider

# Carries every new current-block field plus an hourly block.
RICH_CURRENT_RESPONSE = {
    "timezone": "Asia/Kolkata",
    "current": {
        "time": "2026-09-09T14:00",
        "temperature_2m": 29.8,
        "relative_humidity_2m": 71,
        "weather_code": 0,
        "wind_speed_10m": 2.5,
        "wind_direction_10m": 278,
        "apparent_temperature": 32.4,
        "pressure_msl": 1004.2,
        "dew_point_2m": 21.3,
    },
    "hourly": {
        "time": ["2026-09-09T14:00", "2026-09-09T15:00"],
        "temperature_2m": [29.8, 30.1],
        "weather_code": [0, 1],
    },
}

# Deliberately carries none of them — the shape returned before this change.
BARE_CURRENT_RESPONSE = {
    "timezone": "Asia/Kolkata",
    "current": {
        "time": "2026-09-09T14:00",
        "temperature_2m": 29.8,
        "relative_humidity_2m": 71,
        "weather_code": 0,
        "wind_speed_10m": 2.5,
        "wind_direction_10m": 278,
    },
}


def _provider_returning(payload):
    def handler(request):
        return httpx.Response(200, json=payload)

    return OpenMeteoWeatherProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    )


def test_fetch_current_parses_rich_fields():
    reading = _provider_returning(RICH_CURRENT_RESPONSE).fetch_current(
        latitude=28.61, longitude=77.21
    )

    assert reading.apparent_temperature_c == 32.4
    assert reading.pressure_hpa == 1004.2
    assert reading.dew_point_c == 21.3


def test_fetch_current_zips_the_hourly_block_into_records():
    reading = _provider_returning(RICH_CURRENT_RESPONSE).fetch_current(
        latitude=28.61, longitude=77.21
    )

    assert reading.hourly == [
        {"time": "2026-09-09T14:00", "temperature_c": 29.8, "weather_code": 0},
        {"time": "2026-09-09T15:00", "temperature_c": 30.1, "weather_code": 1},
    ]


def test_fetch_current_tolerates_missing_rich_fields():
    reading = _provider_returning(BARE_CURRENT_RESPONSE).fetch_current(
        latitude=28.61, longitude=77.21
    )

    assert reading.apparent_temperature_c is None
    assert reading.pressure_hpa is None
    assert reading.dew_point_c is None
    assert reading.hourly is None
    # The pre-existing fields still parse.
    assert reading.temperature_c == 29.8
    assert reading.weather_code == 0


def test_fetch_current_actually_requests_the_rich_fields():
    # Without this, the parse tests above would still pass against a
    # fixture containing the fields even if the request stopped asking for
    # them — and the live API would quietly return None for everything.
    seen = {}

    def handler(request):
        seen.update(dict(request.url.params))
        return httpx.Response(200, json=RICH_CURRENT_RESPONSE)

    provider = OpenMeteoWeatherProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    )
    provider.fetch_current(latitude=28.61, longitude=77.21)

    for field in ("apparent_temperature", "pressure_msl", "dew_point_2m"):
        assert field in seen["current"], f"{field} missing from current="
    assert "temperature_2m" in seen["hourly"]
    assert "weather_code" in seen["hourly"]


def test_fetch_forecast_parses_uv_and_sun_times():
    payload = {
        "daily": {
            "time": ["2026-09-09"],
            "weather_code": [61],
            "temperature_2m_max": [31.2],
            "temperature_2m_min": [24.1],
            "precipitation_probability_max": [80],
            "precipitation_sum": [12.0],
            "wind_speed_10m_max": [29.6],
            "uv_index_max": [7.35],
            "sunrise": ["2026-09-09T06:12"],
            "sunset": ["2026-09-09T18:42"],
        }
    }

    days = _provider_returning(payload).fetch_forecast(28.61, 77.21, days=1)

    assert days[0].uv_index_max == 7.35
    # Kept as upstream strings, exactly as forecast_date and observed_at
    # already are — the frontend formats for display.
    assert days[0].sunrise == "2026-09-09T06:12"
    assert days[0].sunset == "2026-09-09T18:42"


def test_fetch_forecast_tolerates_missing_uv_and_sun_times():
    payload = {
        "daily": {
            "time": ["2026-09-09"],
            "weather_code": [61],
            "temperature_2m_max": [31.2],
            "temperature_2m_min": [24.1],
            "precipitation_probability_max": [80],
            "precipitation_sum": [12.0],
            "wind_speed_10m_max": [29.6],
        }
    }

    days = _provider_returning(payload).fetch_forecast(28.61, 77.21, days=1)

    assert days[0].uv_index_max is None
    assert days[0].sunrise is None
    assert days[0].sunset is None
    assert days[0].temp_max_c == 31.2


def test_fetch_forecast_actually_requests_uv_and_sun_times():
    seen = {}

    def handler(request):
        seen.update(dict(request.url.params))
        return httpx.Response(
            200,
            json={
                "daily": {
                    "time": ["2026-09-09"],
                    "weather_code": [61],
                    "temperature_2m_max": [31.2],
                    "temperature_2m_min": [24.1],
                    "precipitation_probability_max": [80],
                    "precipitation_sum": [12.0],
                    "wind_speed_10m_max": [29.6],
                    "uv_index_max": [7.35],
                    "sunrise": ["2026-09-09T06:12"],
                    "sunset": ["2026-09-09T18:42"],
                }
            },
        )

    provider = OpenMeteoWeatherProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    )
    provider.fetch_forecast(28.61, 77.21, days=1)

    for field in ("uv_index_max", "sunrise", "sunset"):
        assert field in seen["daily"], f"{field} missing from daily="


# UV index is an HOURLY field, and reading it from the daily block is the
# specific bug the tests below exist to prevent: a user in Dharwad saw "UV
# index 9 · Very high" at 21:09, because the day's peak was being reported
# as the current value.
NIGHT_RESPONSE = {
    "timezone": "Asia/Kolkata",
    "current": {
        # 21:09 — deliberately off the hour, so the 15-minute `current`
        # granularity has to be matched into the on-the-hour series.
        "time": "2026-09-10T21:09",
        "temperature_2m": 23.0,
        "relative_humidity_2m": 78,
        "weather_code": 3,
        "wind_speed_10m": 8.0,
        "wind_direction_10m": 250,
    },
    "hourly": {
        "time": ["2026-09-10T12:00", "2026-09-10T21:00"],
        "temperature_2m": [31.0, 23.0],
        "weather_code": [1, 3],
        "uv_index": [9.05, 0.0],
    },
}


def test_fetch_current_reads_uv_from_the_matching_hour_not_the_daily_peak():
    reading = _provider_returning(NIGHT_RESPONSE).fetch_current(15.36, 75.12)

    # 0.0 at 21:00 — NOT 9.05, the day's peak at noon.
    assert reading.uv_index == 0.0


def test_fetch_current_requests_uv_index_in_the_hourly_block():
    seen = {}

    def handler(request):
        seen.update(dict(request.url.params))
        return httpx.Response(200, json=NIGHT_RESPONSE)

    OpenMeteoWeatherProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    ).fetch_current(15.36, 75.12)

    assert "uv_index" in seen["hourly"]


def test_fetch_current_leaves_uv_none_when_the_hourly_block_omits_it():
    reading = _provider_returning(RICH_CURRENT_RESPONSE).fetch_current(28.61, 77.21)

    # Absent, not zero — a "0" UV reads as a real measurement.
    assert reading.uv_index is None


def test_fetch_current_leaves_uv_none_when_there_is_no_hourly_block():
    reading = _provider_returning(BARE_CURRENT_RESPONSE).fetch_current(28.61, 77.21)

    assert reading.uv_index is None
