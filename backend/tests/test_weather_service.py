from datetime import datetime, timedelta, timezone

from sqlalchemy import insert, select

from app.db import get_engine
from app.models import WeatherReading
from app.providers.weather import WeatherReadingData
from app.weather.service import get_weather


class _RaisingProvider:
    def fetch_current(self, latitude, longitude):
        raise AssertionError("provider should not be called on a fresh cache hit")


class _FakeWeatherProvider:
    def __init__(self, reading: WeatherReadingData):
        self._reading = reading
        self.calls = 0
        self.received_coordinates = None

    def fetch_current(self, latitude, longitude):
        self.calls += 1
        self.received_coordinates = (latitude, longitude)
        return self._reading


def _seed_reading(fetched_at, temperature_c=28.1):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=temperature_c,
                humidity_pct=79,
                weather_code=51,
                wind_speed_kmh=9.7,
                wind_direction_deg=255,
                observed_at="2026-09-06T12:00",
                timezone="Asia/Kolkata",
                raw_payload={"seeded": True},
                fetched_at=fetched_at,
            )
        )


def test_get_weather_returns_fresh_cache_without_calling_provider(clean_weather_readings):
    _seed_reading(fetched_at=datetime.now(timezone.utc))

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    assert result["temperature_c"] == 28.1
    assert "raw_payload" not in result


def test_get_weather_fetches_and_caches_on_missing_row(clean_weather_readings):
    reading = WeatherReadingData(
        latitude=19.08,
        longitude=72.88,
        temperature_c=30.0,
        humidity_pct=60.0,
        weather_code=1,
        wind_speed_kmh=5.0,
        wind_direction_deg=100.0,
        observed_at="2026-09-06T13:00",
        timezone="Asia/Kolkata",
        raw_payload={"live": True},
    )
    provider = _FakeWeatherProvider(reading)

    result = get_weather(19.08, 72.88, provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 30.0
    assert "raw_payload" not in result

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherReading).where(
                WeatherReading.latitude == 19.08, WeatherReading.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1


def test_get_weather_refetches_when_cache_is_stale(clean_weather_readings):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    _seed_reading(fetched_at=stale_time, temperature_c=10.0)

    reading = WeatherReadingData(
        latitude=19.08,
        longitude=72.88,
        temperature_c=35.0,
        humidity_pct=40.0,
        weather_code=2,
        wind_speed_kmh=15.0,
        wind_direction_deg=200.0,
        observed_at="2026-09-06T14:00",
        timezone="Asia/Kolkata",
        raw_payload={"fresh": True},
    )
    provider = _FakeWeatherProvider(reading)

    result = get_weather(19.08, 72.88, provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 35.0

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherReading).where(
                WeatherReading.latitude == 19.08, WeatherReading.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].temperature_c == 35.0


def test_get_weather_rounds_coordinates_for_cache_key_and_provider_call(
    clean_weather_readings,
):
    reading = WeatherReadingData(
        latitude=19.08,
        longitude=72.88,
        temperature_c=27.0,
        humidity_pct=70.0,
        weather_code=3,
        wind_speed_kmh=8.0,
        wind_direction_deg=180.0,
        observed_at="2026-09-06T15:00",
        timezone="Asia/Kolkata",
        raw_payload={"rounded": True},
    )
    provider = _FakeWeatherProvider(reading)

    result = get_weather(19.0761, 72.8812, provider=provider)

    assert provider.received_coordinates == (19.08, 72.88)
    assert result["latitude"] == 19.08
    assert result["longitude"] == 72.88

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherReading).where(
                WeatherReading.latitude == 19.08, WeatherReading.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1


def test_get_weather_repeat_query_only_calls_provider_once(clean_weather_readings):
    reading = WeatherReadingData(
        latitude=19.08,
        longitude=72.88,
        temperature_c=27.0,
        humidity_pct=70.0,
        weather_code=3,
        wind_speed_kmh=8.0,
        wind_direction_deg=180.0,
        observed_at="2026-09-06T15:00",
        timezone="Asia/Kolkata",
        raw_payload={"once": True},
    )
    provider = _FakeWeatherProvider(reading)

    get_weather(19.08, 72.88, provider=provider)
    get_weather(19.08, 72.88, provider=provider)

    assert provider.calls == 1
