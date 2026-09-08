from sqlalchemy import inspect

from app.db import get_engine


def test_historical_weather_readings_table_has_expected_columns():
    inspector = inspect(get_engine())
    columns = {col["name"] for col in inspector.get_columns("historical_weather_readings")}
    assert columns == {
        "id", "location_name", "latitude", "longitude", "observation_date",
        "temp_2m_c", "dewpoint_2m_c", "precip_mm", "wind_speed_10m_kmh",
        "wind_direction_10m_deg", "mslp_hpa", "fetched_at",
    }


def test_historical_weather_readings_has_unique_constraint_on_location_and_date():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("historical_weather_readings")
    names = {frozenset(c["column_names"]) for c in constraints}
    assert frozenset({"location_name", "observation_date"}) in names
