"""The weather service's hourly window.

The provider stores two full days of hourly data so a request landing late
in the day still has 24 hours ahead of it. The service trims that to a
forward-looking window before responding — the cached row keeps the full
series for any other consumer.
"""

from datetime import datetime, timezone

from sqlalchemy import insert

from app.db import get_engine
from app.models import WeatherReading
from app.weather.service import get_weather


def _hourly(start_hour: int, count: int) -> list[dict]:
    return [
        {
            "time": f"2026-09-09T{(start_hour + i) % 24:02d}:00",
            "temperature_c": 25.0 + i * 0.1,
            "weather_code": 0,
        }
        for i in range(count)
    ]


def _seed(hourly, observed_at="2026-09-09T14:00"):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=29.8,
                humidity_pct=71.0,
                weather_code=0,
                wind_speed_kmh=2.5,
                wind_direction_deg=278.0,
                observed_at=observed_at,
                timezone="Asia/Kolkata",
                raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
                hourly=hourly,
            )
        )


class _RaisingProvider:
    def fetch_current(self, latitude, longitude):
        raise AssertionError("provider should not be called on a fresh cache hit")


def test_hourly_is_trimmed_to_24_entries(clean_weather_readings):
    # 48 hours stored, starting at midnight; observed_at is 14:00.
    _seed(_hourly(start_hour=0, count=24))

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    assert len(result["hourly"]) == 10  # 14:00 through 23:00


def test_hourly_starts_at_the_observed_hour_not_the_start_of_the_series(
    clean_weather_readings,
):
    _seed(_hourly(start_hour=0, count=24))

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    # The window is forward-looking: this morning is not what a user wants.
    assert result["hourly"][0]["time"] == "2026-09-09T14:00"


def test_hourly_caps_a_long_series_at_the_window(clean_weather_readings):
    # A series long enough that the forward-looking slice exceeds 24.
    long_series = [
        {"time": f"2026-09-{9 + i // 24:02d}T{i % 24:02d}:00",
         "temperature_c": 25.0,
         "weather_code": 0}
        for i in range(48)
    ]
    _seed(long_series, observed_at="2026-09-09T00:00")

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    assert len(result["hourly"]) == 24


def test_hourly_survives_a_row_with_no_series(clean_weather_readings):
    # Rows cached before this feature existed have hourly = NULL.
    _seed(None)

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    assert result["hourly"] is None
    # The rest of the reading is unaffected.
    assert result["temperature_c"] == 29.8


def test_hourly_falls_back_to_the_tail_when_the_series_is_all_past(
    clean_weather_readings,
):
    # Shouldn't happen while the TTL works, but showing the tail beats
    # showing nothing if a row goes stale in a way the TTL missed.
    _seed(_hourly(start_hour=0, count=6), observed_at="2026-09-09T23:00")

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    assert len(result["hourly"]) == 6
