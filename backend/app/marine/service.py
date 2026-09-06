"""Query-path read of ingested PFZ zone rows — see app/ingestion/marine.py
for how this table is populated (scheduled-ingestion pattern)."""

from sqlalchemy import select

from app.db import get_engine
from app.models import PfzZone


def list_pfz_zones() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    return [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]
