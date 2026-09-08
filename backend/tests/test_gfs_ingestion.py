from datetime import datetime, timezone

import pytest
from sqlalchemy import insert, select

from app.db import get_engine
from app.ingestion.gfs import ingest_gfs_forecast
from app.models import GfsForecastPoint
from app.providers.nwp import GfsGridPointData


class _FakeGfsProvider:
    def __init__(self, run=("20260908", "00"), points_by_hour=None):
        self._run = run
        self._points_by_hour = points_by_hour or {}

    def discover_latest_run(self):
        return self._run

    def fetch_india_grid(self, run_date, run_hour, forecast_hour):
        return self._points_by_hour.get(forecast_hour, [])


def _point(**overrides):
    base = dict(
        run_date="20260908", run_hour="00", forecast_hour=0,
        valid_time=datetime(2026, 9, 8, tzinfo=timezone.utc),
        grid_latitude=19.0, grid_longitude=73.0,
        temp_2m_c=28.0, relative_humidity_2m_pct=70.0,
        wind_speed_10m_kmh=15.0, wind_direction_10m_deg=180.0,
        wind_gust_kmh=20.0, precip_rate_mmh=0.0,
        cape_j_per_kg=500.0, cin_j_per_kg=-50.0,
        cloud_cover_pct=40.0, mslp_hpa=1010.0,
    )
    base.update(overrides)
    return GfsGridPointData(**base)


def test_ingest_writes_rows_for_every_target_forecast_hour(clean_gfs_forecast_points):
    provider = _FakeGfsProvider(points_by_hour={0: [_point(forecast_hour=0)], 24: [_point(forecast_hour=24)]})
    count = ingest_gfs_forecast(provider, forecast_hours=[0, 24])
    assert count == 2

    with get_engine().connect() as conn:
        rows = conn.execute(select(GfsForecastPoint)).mappings().all()
    assert {r["forecast_hour"] for r in rows} == {0, 24}


def test_ingest_reconciles_away_a_prior_older_run(clean_gfs_forecast_points):
    with get_engine().begin() as conn:
        conn.execute(
            insert(GfsForecastPoint).values(
                run_date="20260907", run_hour="18", forecast_hour=0,
                valid_time=datetime(2026, 9, 7, 18, tzinfo=timezone.utc),
                grid_latitude=19.0, grid_longitude=73.0,
                fetched_at=datetime.now(timezone.utc),
            )
        )

    provider = _FakeGfsProvider(run=("20260908", "00"), points_by_hour={0: [_point(forecast_hour=0)]})
    ingest_gfs_forecast(provider, forecast_hours=[0])

    with get_engine().connect() as conn:
        rows = conn.execute(select(GfsForecastPoint)).mappings().all()
    assert {(r["run_date"], r["run_hour"]) for r in rows} == {("20260908", "00")}


def test_ingest_upserts_on_repeat_call_for_the_same_run(clean_gfs_forecast_points):
    provider = _FakeGfsProvider(points_by_hour={0: [_point(forecast_hour=0, temp_2m_c=28.0)]})
    ingest_gfs_forecast(provider, forecast_hours=[0])

    provider2 = _FakeGfsProvider(points_by_hour={0: [_point(forecast_hour=0, temp_2m_c=30.0)]})
    ingest_gfs_forecast(provider2, forecast_hours=[0])

    with get_engine().connect() as conn:
        rows = conn.execute(select(GfsForecastPoint)).mappings().all()
    assert len(rows) == 1
    assert rows[0]["temp_2m_c"] == 30.0


def test_ingest_with_no_points_for_an_hour_does_not_crash(clean_gfs_forecast_points):
    provider = _FakeGfsProvider(points_by_hour={0: []})
    count = ingest_gfs_forecast(provider, forecast_hours=[0])
    assert count == 0


def test_ingest_of_an_entirely_empty_fetch_leaves_existing_rows_untouched(
    clean_gfs_forecast_points,
):
    # An empty fetch is indistinguishable from a provider-side bug, so
    # reconciliation must NOT run and wholesale-delete the previous run.
    with get_engine().begin() as conn:
        conn.execute(
            insert(GfsForecastPoint).values(
                run_date="20260907", run_hour="18", forecast_hour=0,
                valid_time=datetime(2026, 9, 7, 18, tzinfo=timezone.utc),
                grid_latitude=19.0, grid_longitude=73.0,
                temp_2m_c=25.0, fetched_at=datetime.now(timezone.utc),
            )
        )

    provider = _FakeGfsProvider(run=("20260908", "00"), points_by_hour={})
    assert ingest_gfs_forecast(provider, forecast_hours=[0, 24]) == 0

    with get_engine().connect() as conn:
        rows = conn.execute(select(GfsForecastPoint)).mappings().all()
    assert len(rows) == 1
    assert (rows[0]["run_date"], rows[0]["run_hour"]) == ("20260907", "18")


def test_ingest_failure_partway_through_leaves_old_run_fully_intact(clean_gfs_forecast_points):
    # Seed an OLDER run's data.
    with get_engine().begin() as conn:
        conn.execute(
            insert(GfsForecastPoint).values(
                run_date="20260907", run_hour="18", forecast_hour=0,
                valid_time=datetime(2026, 9, 7, 18, tzinfo=timezone.utc),
                grid_latitude=19.0, grid_longitude=73.0,
                temp_2m_c=25.0, fetched_at=datetime.now(timezone.utc),
            )
        )
        conn.execute(
            insert(GfsForecastPoint).values(
                run_date="20260907", run_hour="18", forecast_hour=24,
                valid_time=datetime(2026, 9, 8, 18, tzinfo=timezone.utc),
                grid_latitude=19.0, grid_longitude=73.0,
                temp_2m_c=26.0, fetched_at=datetime.now(timezone.utc),
            )
        )

    class _FailingProvider:
        def __init__(self):
            self.calls = 0

        def discover_latest_run(self):
            return ("20260908", "00")

        def fetch_india_grid(self, run_date, run_hour, forecast_hour):
            self.calls += 1
            if self.calls == 3:
                raise RuntimeError("simulated network failure on the 3rd forecast hour")
            return [_point(forecast_hour=forecast_hour, run_date=run_date, run_hour=run_hour)]

    provider = _FailingProvider()
    with pytest.raises(RuntimeError, match="simulated network failure"):
        ingest_gfs_forecast(provider, forecast_hours=[0, 24, 48, 72, 96, 120])

    with get_engine().connect() as conn:
        rows = conn.execute(select(GfsForecastPoint)).mappings().all()

    # The OLD run must be 100% intact — not partially overwritten, not
    # partially deleted, and there must be ZERO rows from the new
    # (failed) run, even though 2 of its 6 forecast hours "succeeded"
    # before the 3rd one raised.
    assert len(rows) == 2
    assert {(r["run_date"], r["run_hour"]) for r in rows} == {("20260907", "18")}
    assert {r["temp_2m_c"] for r in rows} == {25.0, 26.0}
