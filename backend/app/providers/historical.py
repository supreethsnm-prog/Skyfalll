"""HistoricalWeatherProvider: ERA5 reanalysis data (spec section 4's
"Historical/climate" requirement). Unlike every other provider in this
codebase, this is never called at request time or on any scheduled
interval — see app/providers/era5.py's module docstring for why: a single
CDS request takes 25 seconds to 2 minutes (confirmed live), categorically
incompatible with an HTTP request cycle or a short polling interval.

`fetch_reading` is declared as returning `Era5ReadingData | None` so that
future implementations (a cache-backed or file-backed historical source,
say) can report "no data for this (location, date)" without inventing an
exception type. `CdsEra5Provider`, the only implementation today, never
takes that branch: every CDS failure mode observed live surfaces as a
raised exception, so it either returns a fully-populated reading or
raises. Callers should still handle `None` defensively.
"""

from dataclasses import dataclass
from typing import Protocol


@dataclass
class Era5ReadingData:
    location_name: str
    latitude: float
    longitude: float
    observation_date: str
    temp_2m_c: float | None
    dewpoint_2m_c: float | None
    precip_mm: float | None
    wind_speed_10m_kmh: float | None
    wind_direction_10m_deg: float | None
    mslp_hpa: float | None


class HistoricalWeatherProvider(Protocol):
    def fetch_reading(
        self, location_name: str, latitude: float, longitude: float, observation_date: str
    ) -> Era5ReadingData | None: ...
