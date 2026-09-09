"""The hourly window must include the hour the user is currently in.

`observed_at` carries 15-minute granularity ("...T20:45") while the series
is on the hour ("...T20:00"). Comparing the raw strings makes 20:00 sort
BEFORE 20:45 and get dropped, so the strip silently starts an hour late
and the "Now" column shows the next hour instead.

The fixture below uses an off-the-hour observed_at deliberately; an
on-the-hour one would pass against the broken comparison.
"""

from datetime import datetime, timezone

from sqlalchemy import insert

from app.db import get_engine
from app.models import WeatherReading
from app.weather.service import get_weather


class _RaisingProvider:
    def fetch_current(self, latitude, longitude):
        raise AssertionError("provider should not be called on a fresh cache hit")


def _seed(observed_at):
    hourly = [
        {
            "time": f"2026-09-09T{h:02d}:00",
            "temperature_c": 25.0 + h * 0.1,
            "weather_code": 0,
        }
        for h in range(24)
    ]
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=26.8,
                humidity_pct=64.0,
                weather_code=2,
                wind_speed_kmh=7.1,
                wind_direction_deg=240.0,
                observed_at=observed_at,
                timezone="Asia/Kolkata",
                raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
                hourly=hourly,
            )
        )


def test_window_includes_the_current_hour(clean_weather_readings):
    _seed("2026-09-09T20:45")

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    # 20:00 is the hour containing 20:45, so it leads the strip.
    assert result["hourly"][0]["time"] == "2026-09-09T20:00"


def test_window_still_works_for_an_on_the_hour_reading(clean_weather_readings):
    _seed("2026-09-09T20:00")

    result = get_weather(19.08, 72.88, provider=_RaisingProvider())

    assert result["hourly"][0]["time"] == "2026-09-09T20:00"
