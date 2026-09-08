from datetime import datetime, timezone

from sqlalchemy import insert

from app.db import get_engine
from app.models import GfsForecastPoint
from app.nwp.service import get_nwp_forecast


def _seed_point(**overrides):
    base = dict(
        run_date="20260908", run_hour="00", forecast_hour=0,
        valid_time=datetime(2026, 9, 8, tzinfo=timezone.utc),
        grid_latitude=19.0, grid_longitude=73.0,
        temp_2m_c=28.0, fetched_at=datetime.now(timezone.utc),
    )
    base.update(overrides)
    with get_engine().begin() as conn:
        conn.execute(insert(GfsForecastPoint).values(**base))


def test_snaps_an_arbitrary_coordinate_to_the_nearest_grid_point(clean_gfs_forecast_points):
    _seed_point(grid_latitude=19.0, grid_longitude=73.0, temp_2m_c=28.0)
    result = get_nwp_forecast(latitude=19.08, longitude=72.88)  # real Mumbai coordinate, nearest 0.25 grid point is (19.0, 73.0)
    assert len(result) == 1
    assert result[0]["temp_2m_c"] == 28.0


def test_out_of_india_bbox_coordinate_returns_empty(clean_gfs_forecast_points):
    _seed_point()
    result = get_nwp_forecast(latitude=51.5, longitude=-0.1)  # London
    assert result == []


def test_returns_multiple_forecast_hours_sorted(clean_gfs_forecast_points):
    _seed_point(forecast_hour=24, temp_2m_c=30.0, grid_latitude=19.0, grid_longitude=73.0)
    _seed_point(forecast_hour=0, temp_2m_c=28.0, grid_latitude=19.0, grid_longitude=73.0)
    result = get_nwp_forecast(latitude=19.0, longitude=73.0)
    assert [r["forecast_hour"] for r in result] == [0, 24]


def test_filters_to_requested_forecast_hours(clean_gfs_forecast_points):
    _seed_point(forecast_hour=0, grid_latitude=19.0, grid_longitude=73.0)
    _seed_point(forecast_hour=48, grid_latitude=19.0, grid_longitude=73.0)
    result = get_nwp_forecast(latitude=19.0, longitude=73.0, forecast_hours=[0])
    assert [r["forecast_hour"] for r in result] == [0]


def test_no_raw_payload_or_grid_coordinates_leak_into_response(clean_gfs_forecast_points):
    _seed_point()
    result = get_nwp_forecast(latitude=19.0, longitude=73.0)
    assert "grid_latitude" not in result[0]
    assert "grid_longitude" not in result[0]
    assert "id" not in result[0]
