from sqlalchemy import inspect

from app.db import get_engine


def test_metar_readings_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "metar_readings" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("metar_readings")}
    assert columns == {
        "id",
        "icao_id",
        "raw_metar",
        "observed_at",
        "temperature_c",
        "dewpoint_c",
        "wind_dir_deg",
        "wind_speed_kt",
        "visibility_sm",
        "flight_category",
        "station_name",
        "latitude",
        "longitude",
        "raw_payload",
        "fetched_at",
    }


def test_metar_readings_has_unique_constraint_on_icao_id():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("metar_readings")
    matching = [c for c in constraints if c["column_names"] == ["icao_id"]]
    assert len(matching) == 1
