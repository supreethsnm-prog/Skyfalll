"""Populate every data source before a demo.

Several of WeatherGPT's screens read from tables that are filled by
scheduled ingestion rather than on demand. Those schedulers only fire on
an interval, the dev server restarts constantly, and **the test suite
truncates every table it touches** — so it is entirely normal to sit down
to demo and find alerts, marine zones and NWP all empty, with the app
correctly showing empty states for data that simply was never loaded.

Run this before presenting:

    .venv\\Scripts\\python -m scripts.prime_demo

It is safe to re-run: every step upserts.

NOT covered here: ERA5 historical (`scripts/seed_era5_history.py`). That
one takes 20-40 minutes against the Copernicus API and is deliberately
kept separate so this script stays fast enough to run minutes before a
demo.
"""

from __future__ import annotations

import logging
import sys
import time
from dataclasses import dataclass
from typing import Callable

logging.basicConfig(level=logging.WARNING)

# Cities the demo moves between. Warming these means the first tap in
# front of an audience hits a cache rather than a cold upstream call —
# and, more importantly, that a rate-limited or briefly-down provider
# cannot embarrass you live.
DEMO_LOCATIONS: list[tuple[str, float, float]] = [
    ("New Delhi", 28.6139, 77.2090),
    ("Pune", 18.5204, 73.8567),
    # Live IMD flood warnings sit on the Ganga and Bagmati; these are the
    # locations where the alert banner actually appears.
    ("Bhagalpur", 25.2700, 87.2300),
    ("Muzaffarpur", 26.1200, 85.3900),
    ("Mumbai", 19.0760, 72.8777),
]


@dataclass
class Step:
    name: str
    run: Callable[[], str]
    # A step that fails should not stop the others: a demo with four of
    # five sources primed is far better than one that aborted on the first
    # flaky upstream.
    critical: bool = False


def _ingest_alerts() -> str:
    from app.ingestion.alerts import ingest_alerts
    from app.providers.sachet import SACHETWarningProvider

    return f"{ingest_alerts(SACHETWarningProvider())} alerts"


def _ingest_marine() -> str:
    from app.ingestion.marine import ingest_pfz_zones
    from app.providers.incois import INCOISMarineProvider

    return f"{ingest_pfz_zones(INCOISMarineProvider())} PFZ zones"


def _ingest_gfs() -> str:
    from app.ingestion.gfs import ingest_gfs_forecast

    return f"{ingest_gfs_forecast()} NWP grid points"


def _warm_point_caches() -> str:
    from app.air_quality.service import get_air_quality
    from app.forecast.service import get_forecast
    from app.weather.service import get_weather

    warmed = 0
    for name, lat, lon in DEMO_LOCATIONS:
        for label, call in (
            ("weather", lambda: get_weather(lat, lon)),
            ("forecast", lambda: get_forecast(lat, lon, days=5)),
            ("air quality", lambda: get_air_quality(lat, lon)),
        ):
            try:
                call()
                warmed += 1
            except Exception as exc:  # noqa: BLE001 - report and continue
                print(f"    ! {name} {label}: {type(exc).__name__}")
    return f"{warmed} point caches warmed"


def _restore_era5() -> str:
    # Restores from a local snapshot rather than re-fetching: a real ERA5
    # seed is 25s-2min PER ROW against Copernicus, and the test suite
    # truncates this table like every other. Re-seeding after each pytest
    # run would cost half an hour, which is why historical data had simply
    # stayed empty. See scripts/era5_snapshot.py.
    from scripts.era5_snapshot import SNAPSHOT_PATH, restore

    if not SNAPSHOT_PATH.exists():
        return "skipped — no snapshot (run scripts/seed_era5_history.py, then `era5_snapshot save`)"
    return f"{restore()} historical rows restored"


def _check_advisories() -> str:
    # Advisories are computed on demand from the forecast cache, so there
    # is nothing to ingest — but calling them proves the rules run and
    # surfaces a broken skill before an audience does.
    from app.skills.agriculture import get_agriculture_advisory
    from app.skills.urban import get_urban_advisory

    total = 0
    for _, lat, lon in DEMO_LOCATIONS[:2]:
        total += len(get_agriculture_advisory(lat, lon)["advisories"])
        total += len(get_urban_advisory(lat, lon)["advisories"])
    return f"advisory rules OK ({total} advisories across 2 cities)"


STEPS = [
    Step("Alerts (SACHET/IMD)", _ingest_alerts, critical=True),
    Step("Marine PFZ (INCOIS)", _ingest_marine),
    Step("NWP (NOAA GFS)", _ingest_gfs),
    Step("Point caches", _warm_point_caches),
    Step("ERA5 historical", _restore_era5),
    Step("Advisories", _check_advisories),
]


def main() -> int:
    print("Priming WeatherGPT demo data\n")
    failures: list[str] = []

    for step in STEPS:
        print(f"  {step.name} ...", end=" ", flush=True)
        started = time.monotonic()
        try:
            detail = step.run()
            print(f"OK — {detail}  ({time.monotonic() - started:.1f}s)")
        except Exception as exc:  # noqa: BLE001 - a demo script reports, not raises
            print(f"FAILED — {type(exc).__name__}: {exc}")
            failures.append(step.name)
            if step.critical:
                print(
                    "\n    ^ This one matters: without alerts the disaster-warning\n"
                    "      demo has nothing to show."
                )

    print()
    if failures:
        print(f"Done with {len(failures)} failure(s): {', '.join(failures)}")
        print("Everything else is primed; re-run to retry the failures.")
        return 1

    print("All sources primed.")
    print(
        "\nReminder: running the backend test suite truncates these tables.\n"
        "Re-run this script after any pytest run."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
