from sqlalchemy import inspect

from app.db import get_engine


def test_alerts_table_exists_with_expected_columns():
    inspector = inspect(get_engine())
    assert "alerts" in inspector.get_table_names()
    columns = {col["name"] for col in inspector.get_columns("alerts")}
    assert columns == {
        "id",
        "external_id",
        "source",
        "severity",
        "event_type",
        "area_description",
        "effective_start_time",
        "effective_end_time",
        "warning_message",
        "severity_color",
        "latitude",
        "longitude",
        "raw_payload",
        "fetched_at",
    }
