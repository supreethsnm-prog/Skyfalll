from sqlalchemy import inspect

from app.db import get_engine


def test_geocode_cache_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "geocode_cache" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("geocode_cache")}
    assert columns == {
        "id",
        "query",
        "display_name",
        "latitude",
        "longitude",
        "country",
        "state",
        "raw_payload",
        "fetched_at",
    }


def test_geocode_cache_has_unique_constraint_on_query():
    inspector = inspect(get_engine())
    constraints = inspector.get_unique_constraints("geocode_cache")
    matching = [c for c in constraints if c["column_names"] == ["query"]]
    assert len(matching) == 1
