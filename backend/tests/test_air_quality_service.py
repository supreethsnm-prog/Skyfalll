from datetime import datetime, timedelta, timezone

from sqlalchemy import insert, select

from app.air_quality.service import get_air_quality
from app.db import get_engine
from app.models import AirQualityReading
from app.providers.air_quality import AirQualityData


class _FakeProvider:
    def __init__(self, reading: AirQualityData):
        self._reading = reading
        self.calls = 0

    def fetch_current(self, latitude, longitude):
        self.calls += 1
        return self._reading


def _sample(us_aqi=156.0):
    return AirQualityData(
        latitude=28.61,
        longitude=77.21,
        observed_at="2026-09-09T14:00",
        raw_payload={"live": True},
        us_aqi=us_aqi,
        pm2_5=64.8,
        pm10=118.2,
    )


def _seed(fetched_at, us_aqi=42.0):
    with get_engine().begin() as conn:
        conn.execute(
            insert(AirQualityReading).values(
                latitude=28.61,
                longitude=77.21,
                observed_at="2026-09-09T09:00",
                raw_payload={"seeded": True},
                fetched_at=fetched_at,
                us_aqi=us_aqi,
                pm2_5=10.0,
                pm10=20.0,
            )
        )


def test_fetches_and_caches_on_missing_row(clean_air_quality_readings):
    provider = _FakeProvider(_sample())

    result = get_air_quality(28.61, 77.21, provider=provider)

    assert provider.calls == 1
    assert result["us_aqi"] == 156.0
    assert result["pm2_5"] == 64.8
    # raw_payload is storage, not response.
    assert "raw_payload" not in result

    with get_engine().connect() as conn:
        rows = conn.execute(select(AirQualityReading)).fetchall()
    assert len(rows) == 1


def test_returns_fresh_cache_without_calling_provider(clean_air_quality_readings):
    _seed(datetime.now(timezone.utc))

    class _Raising:
        def fetch_current(self, latitude, longitude):
            raise AssertionError("provider should not be called on a fresh hit")

    result = get_air_quality(28.61, 77.21, provider=_Raising())

    assert result["us_aqi"] == 42.0


def test_refetches_when_cache_is_stale(clean_air_quality_readings):
    # Older than the 60-minute window.
    _seed(datetime.now(timezone.utc) - timedelta(minutes=61))
    provider = _FakeProvider(_sample())

    result = get_air_quality(28.61, 77.21, provider=provider)

    assert provider.calls == 1
    assert result["us_aqi"] == 156.0


def test_air_quality_window_is_longer_than_weather(clean_air_quality_readings):
    # 40 minutes would be stale for weather (20-minute window) but is
    # still fresh here. Pins the deliberate difference rather than leaving
    # it to a comment.
    _seed(datetime.now(timezone.utc) - timedelta(minutes=40))

    class _Raising:
        def fetch_current(self, latitude, longitude):
            raise AssertionError("40 minutes should still be fresh for air quality")

    result = get_air_quality(28.61, 77.21, provider=_Raising())

    assert result["us_aqi"] == 42.0


def test_serves_stale_cache_when_provider_fails(clean_air_quality_readings):
    _seed(datetime.now(timezone.utc) - timedelta(hours=5))

    class _Failing:
        def fetch_current(self, latitude, longitude):
            raise RuntimeError("upstream down")

    result = get_air_quality(28.61, 77.21, provider=_Failing())

    # Stale air quality beats no air quality.
    assert result["us_aqi"] == 42.0


def test_upsert_does_not_duplicate_rows(clean_air_quality_readings):
    get_air_quality(28.61, 77.21, provider=_FakeProvider(_sample(100.0)))
    _seed_stale = datetime.now(timezone.utc) - timedelta(hours=2)
    with get_engine().begin() as conn:
        conn.execute(
            AirQualityReading.__table__.update().values(fetched_at=_seed_stale)
        )

    get_air_quality(28.61, 77.21, provider=_FakeProvider(_sample(180.0)))

    with get_engine().connect() as conn:
        rows = conn.execute(select(AirQualityReading)).fetchall()
    assert len(rows) == 1


def test_rounds_coordinates_for_the_cache_key(clean_air_quality_readings):
    provider = _FakeProvider(_sample())

    get_air_quality(28.6139, 77.2090, provider=provider)

    with get_engine().connect() as conn:
        row = conn.execute(select(AirQualityReading)).mappings().one()
    assert row["latitude"] == 28.61
    assert row["longitude"] == 77.21
