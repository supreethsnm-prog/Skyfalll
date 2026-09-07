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


def test_fetch_forecast_zips_daily_arrays_into_one_record_per_day():
    payload = {
        "daily": {
            "time": ["2026-09-07", "2026-09-08"],
            "weather_code": [51, 53],
            "temperature_2m_max": [28.2, 28.6],
            "temperature_2m_min": [25.0, 25.3],
            "precipitation_probability_max": [100, 96],
            "precipitation_sum": [4.4, 4.4],
            "wind_speed_10m_max": [13.9, 15.3],
        }
    }

    def handler(request):
        return httpx.Response(200, json=payload)

    provider = OpenMeteoWeatherProvider(client=httpx.Client(transport=httpx.MockTransport(handler)))

    days = provider.fetch_forecast(19.05, 72.87, days=2)

    assert len(days) == 2
    assert days[0].forecast_date == "2026-09-07"
    assert days[0].weather_code == 51
    assert days[0].temp_max_c == 28.2
    assert days[0].temp_min_c == 25.0
    assert days[0].precip_probability_pct == 100
    assert days[0].precip_sum_mm == 4.4
    assert days[0].wind_speed_max_kmh == 13.9
    assert days[1].forecast_date == "2026-09-08"
    assert days[1].temp_max_c == 28.6


def test_fetch_forecast_handles_missing_precip_probability():
    payload = {
        "daily": {
            "time": ["2026-09-07"],
            "weather_code": [51],
            "temperature_2m_max": [28.2],
            "temperature_2m_min": [25.0],
            "precipitation_probability_max": [None],
            "precipitation_sum": [4.4],
            "wind_speed_10m_max": [13.9],
        }
    }

    def handler(request):
        return httpx.Response(200, json=payload)

    provider = OpenMeteoWeatherProvider(client=httpx.Client(transport=httpx.MockTransport(handler)))
    days = provider.fetch_forecast(19.05, 72.87, days=1)

    assert days[0].precip_probability_pct is None
