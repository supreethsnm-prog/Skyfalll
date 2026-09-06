from sqlalchemy import inspect

from app.db import get_engine


def test_pfz_zones_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "pfz_zones" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("pfz_zones")}
    assert columns == {
        "id",
        "external_id",
        "category",
        "sector_boundary",
        "sector_name",
        "julian_day",
        "serial_number",
        "year",
        "uid",
        "length_km",
        "geometry",
        "raw_payload",
        "fetched_at",
    }


def test_pfz_zones_has_unique_constraint_on_external_id():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("pfz_zones")
    matching = [c for c in constraints if c["column_names"] == ["external_id"]]
    assert len(matching) == 1
