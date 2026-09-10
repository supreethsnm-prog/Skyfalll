"""Save and restore the ERA5 historical table from a local file.

ERA5 rows are expensive: each one is a live Copernicus CDS request taking
25 seconds to 2 minutes, so the standard seed matrix costs 20-40 minutes.
They are also fragile in development, because **the test suite truncates
`historical_weather_readings` like every other table** — so a single
`pytest` run destroys half an hour of fetching.

That combination makes historical data effectively unusable in a working
dev loop, which is why it has stayed empty. This script breaks the tie:

    # Once, after a real seed (slow, hits CDS):
    .venv\\Scripts\\python -m scripts.era5_snapshot save

    # Any time after a test run wipes the table (instant, no network):
    .venv\\Scripts\\python -m scripts.era5_snapshot restore

The snapshot is real observed data, not fixtures — it is exactly what CDS
returned, kept verbatim. Restoring is an upsert, so it never fights a
newer real seed.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import get_engine
from app.models import HistoricalWeatherReading

SNAPSHOT_PATH = Path(__file__).resolve().parent / "era5_snapshot.json"

_FIELDS = (
    "location_name",
    "observation_date",
    "latitude",
    "longitude",
    "temp_2m_c",
    "dewpoint_2m_c",
    "precip_mm",
    "wind_speed_10m_kmh",
    "wind_direction_10m_deg",
    "mslp_hpa",
)


def save() -> int:
    with get_engine().connect() as conn:
        rows = conn.execute(select(HistoricalWeatherReading)).mappings().all()

    if not rows:
        print(
            "Table is empty — nothing to save.\n"
            "Seed it first: .venv\\Scripts\\python scripts/seed_era5_history.py"
        )
        return 0

    payload = [{field: row[field] for field in _FIELDS} for row in rows]
    SNAPSHOT_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    locations = sorted({r["location_name"] for r in payload})
    print(f"Saved {len(payload)} rows to {SNAPSHOT_PATH.name}")
    print(f"  locations: {', '.join(locations)}")
    return len(payload)


def restore() -> int:
    if not SNAPSHOT_PATH.exists():
        print(f"No snapshot at {SNAPSHOT_PATH.name} — run `save` after a seed.")
        return 0

    payload = json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))
    if not payload:
        print("Snapshot is empty.")
        return 0

    # fetched_at is deliberately stamped NOW rather than preserved: it
    # records when this row entered the table, and the reading itself is a
    # fixed historical observation whose value does not go stale.
    fetched_at = datetime.now(timezone.utc)

    with get_engine().begin() as conn:
        for row in payload:
            values = dict(row)
            values["fetched_at"] = fetched_at
            stmt = pg_insert(HistoricalWeatherReading).values(**values)
            conn.execute(
                stmt.on_conflict_do_update(
                    index_elements=[
                        HistoricalWeatherReading.location_name,
                        HistoricalWeatherReading.observation_date,
                    ],
                    set_={
                        col: getattr(stmt.excluded, col)
                        for col in _FIELDS
                        if col not in ("location_name", "observation_date")
                    },
                )
            )

    print(f"Restored {len(payload)} ERA5 rows (no network calls).")
    return len(payload)


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "save":
        save()
        return 0
    if command == "restore":
        restore()
        return 0

    print(__doc__)
    print("Usage: python -m scripts.era5_snapshot [save|restore]")
    return 2


if __name__ == "__main__":
    sys.exit(main())
