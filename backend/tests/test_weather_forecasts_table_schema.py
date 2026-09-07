from sqlalchemy import inspect

from app.db import get_engine


def test_weather_forecasts_table_has_expected_columns():
    inspector = inspect(get_engine())
    columns = {col["name"] for col in inspector.get_columns("weather_forecasts")}
    assert columns == {
        "id", "latitude", "longitude", "forecast_date", "weather_code",
        "temp_max_c", "temp_min_c", "precip_probability_pct", "precip_sum_mm",
        "wind_speed_max_kmh", "raw_payload", "fetched_at",
    }


def test_weather_forecasts_has_composite_unique_constraint():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("weather_forecasts")
    column_sets = [set(c["column_names"]) for c in constraints]
    assert {"latitude", "longitude", "forecast_date"} in column_sets
