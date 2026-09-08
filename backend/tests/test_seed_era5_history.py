from datetime import datetime, timezone

from sqlalchemy import select

from app.db import get_engine
from app.models import HistoricalWeatherReading
from app.providers.historical import Era5ReadingData
from scripts.seed_era5_history import seed_era5_history


class _FakeProvider:
    def __init__(self, fail_for: set[tuple[str, str]] | None = None):
        self._fail_for = fail_for or set()

    def fetch_reading(self, location_name, latitude, longitude, observation_date):
        if (location_name, observation_date) in self._fail_for:
            raise RuntimeError("simulated CDS failure")
        return Era5ReadingData(
            location_name=location_name, latitude=latitude, longitude=longitude,
            observation_date=observation_date, temp_2m_c=25.0, dewpoint_2m_c=20.0,
            precip_mm=1.0, wind_speed_10m_kmh=10.0, wind_direction_10m_deg=180.0,
            mslp_hpa=1010.0,
        )


class _NoneReturningProvider:
    """Simulates a HistoricalWeatherProvider implementation that takes the
    `Era5ReadingData | None` branch of the Protocol instead of raising. Task
    2's real CdsEra5Provider never does this today, but the seed script is
    written against the Protocol, not just that one implementation."""

    def fetch_reading(self, location_name, latitude, longitude, observation_date):
        return None


def test_seed_writes_a_row_per_matrix_entry(clean_historical_weather_readings):
    matrix = [("Mumbai", 19.08, 72.88, "2023-07-15"), ("Delhi", 28.61, 77.21, "2023-01-15")]
    summary = seed_era5_history(_FakeProvider(), matrix=matrix)

    assert summary["succeeded"] == 2
    assert summary["failed"] == 0

    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()
    assert {(r["location_name"], r["observation_date"]) for r in rows} == {
        ("Mumbai", "2023-07-15"), ("Delhi", "2023-01-15"),
    }


def test_seed_continues_past_a_single_failure_and_reports_it(clean_historical_weather_readings):
    matrix = [("Mumbai", 19.08, 72.88, "2023-07-15"), ("Delhi", 28.61, 77.21, "2023-01-15")]
    provider = _FakeProvider(fail_for={("Mumbai", "2023-07-15")})
    summary = seed_era5_history(provider, matrix=matrix)

    assert summary["succeeded"] == 1
    assert summary["failed"] == 1

    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()
    assert [r["location_name"] for r in rows] == ["Delhi"]


def test_seed_upserts_on_repeat_run_for_the_same_matrix_entry(clean_historical_weather_readings):
    matrix = [("Mumbai", 19.08, 72.88, "2023-07-15")]
    seed_era5_history(_FakeProvider(), matrix=matrix)
    seed_era5_history(_FakeProvider(), matrix=matrix)  # rerun — must not duplicate

    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()
    assert len(rows) == 1


def test_seed_treats_a_none_return_as_a_failure_not_a_crash(clean_historical_weather_readings):
    matrix = [("Mumbai", 19.08, 72.88, "2023-07-15"), ("Delhi", 28.61, 77.21, "2023-01-15")]
    provider = _FakeProvider(fail_for=set())
    # Mix a provider that returns None for one entry with one that succeeds,
    # by wrapping per-call behavior directly.
    class _MixedProvider:
        def fetch_reading(self, location_name, latitude, longitude, observation_date):
            if location_name == "Mumbai":
                return None
            return provider.fetch_reading(location_name, latitude, longitude, observation_date)

    summary = seed_era5_history(_MixedProvider(), matrix=matrix)

    assert summary["succeeded"] == 1
    assert summary["failed"] == 1

    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()
    assert [r["location_name"] for r in rows] == ["Delhi"]


def test_seed_all_none_returns_reports_all_failed_without_crashing(clean_historical_weather_readings):
    matrix = [("Mumbai", 19.08, 72.88, "2023-07-15"), ("Delhi", 28.61, 77.21, "2023-01-15")]
    summary = seed_era5_history(_NoneReturningProvider(), matrix=matrix)

    assert summary["succeeded"] == 0
    assert summary["failed"] == 2

    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()
    assert rows == []
