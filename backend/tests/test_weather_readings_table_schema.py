from sqlalchemy import inspect

from app.db import get_engine


def test_weather_readings_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "weather_readings" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("weather_readings")}
    assert columns == {
        "id",
        "latitude",
        "longitude",
        "temperature_c",
        "humidity_pct",
        "weather_code",
        "wind_speed_kmh",
        "wind_direction_deg",
        "observed_at",
        "timezone",
        "raw_payload",
        "fetched_at",
    }


def test_weather_readings_has_unique_constraint_on_lat_lon():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("weather_readings")
    matching = [
        c for c in constraints if set(c["column_names"]) == {"latitude", "longitude"}
    ]
    assert len(matching) == 1
