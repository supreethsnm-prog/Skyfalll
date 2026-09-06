"""Query-path read of ingested alert rows — see app/ingestion/alerts.py for
how this table is populated (scheduled-ingestion pattern)."""

from sqlalchemy import select

from app.db import get_engine
from app.models import Alert


def list_alerts() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    return [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]
