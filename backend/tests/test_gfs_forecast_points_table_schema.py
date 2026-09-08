from sqlalchemy import inspect

from app.db import get_engine


def test_gfs_forecast_points_table_has_expected_columns():
    inspector = inspect(get_engine())
    columns = {col["name"] for col in inspector.get_columns("gfs_forecast_points")}
    assert columns == {
        "id", "run_date", "run_hour", "forecast_hour", "valid_time",
        "grid_latitude", "grid_longitude", "temp_2m_c", "relative_humidity_2m_pct",
        "wind_speed_10m_kmh", "wind_direction_10m_deg", "wind_gust_kmh",
        "precip_rate_mmh", "cape_j_per_kg", "cin_j_per_kg", "cloud_cover_pct",
        "mslp_hpa", "fetched_at",
    }


def test_gfs_forecast_points_has_composite_unique_constraint():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("gfs_forecast_points")
    names = {frozenset(c["column_names"]) for c in constraints}
    assert frozenset(
        {"run_date", "run_hour", "forecast_hour", "grid_latitude", "grid_longitude"}
    ) in names
