import httpx

from app.providers.open_meteo import OpenMeteoWeatherProvider

SAMPLE_RESPONSE = {
    "latitude": 19.086115,
    "longitude": 72.85291,
    "generationtime_ms": 0.125,
    "utc_offset_seconds": 19800,
    "timezone": "Asia/Kolkata",
    "timezone_abbreviation": "GMT+5:30",
    "elevation": 6.0,
    "current_units": {
        "time": "iso8601",
        "interval": "seconds",
        "temperature_2m": "°C",
        "relative_humidity_2m": "%",
        "weather_code": "wmo code",
        "wind_speed_10m": "km/h",
        "wind_direction_10m": "°",
    },
    "current": {
        "time": "2026-09-06T12:00",
        "interval": 900,
        "temperature_2m": 28.1,
        "relative_humidity_2m": 79,
        "weather_code": 51,
        "wind_speed_10m": 9.7,
        "wind_direction_10m": 255,
    },
}


def _handler(request: httpx.Request) -> httpx.Response:
    assert request.url.path == "/v1/forecast"
    return httpx.Response(200, json=SAMPLE_RESPONSE)


def test_fetch_current_normalizes_response_and_preserves_input_coordinates():
    client = httpx.Client(transport=httpx.MockTransport(_handler))
    provider = OpenMeteoWeatherProvider(client=client)

    reading = provider.fetch_current(latitude=19.08, longitude=72.88)

    # Input coordinates are preserved, NOT Open-Meteo's snapped response coordinates.
    assert reading.latitude == 19.08
    assert reading.longitude == 72.88
    assert reading.temperature_c == 28.1
    assert reading.humidity_pct == 79
    assert reading.weather_code == 51
    assert reading.wind_speed_kmh == 9.7
    assert reading.wind_direction_deg == 255
    assert reading.observed_at == "2026-09-06T12:00"
    assert reading.timezone == "Asia/Kolkata"
    assert reading.raw_payload == SAMPLE_RESPONSE
