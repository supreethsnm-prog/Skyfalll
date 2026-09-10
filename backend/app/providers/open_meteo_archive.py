"""Open-Meteo Archive API provider: daily ERA5/ERA5-Land reanalysis for any
location on Earth from 1940 to ~5 days ago, with no API key.

Confirmed live against the real endpoint (2026-09-10):

    https://archive-api.open-meteo.com/v1/archive?latitude=15.36&longitude=75.12
        &start_date=2024-07-15&end_date=2024-07-15
        &daily=temperature_2m_max,temperature_2m_min,temperature_2m_mean,
               precipitation_sum,windspeed_10m_max,winddirection_10m_dominant
        &timezone=auto

which returned a `daily` block of parallel one-element arrays keyed by
those same field names (`windspeed_10m_max` / `winddirection_10m_dominant`,
not the `wind_speed_10m_max` spelling `api.open-meteo.com` uses).

This is itself ERA5/ERA5-Land reanalysis, so the app's existing "Source:
ECMWF ERA5 reanalysis" provenance line stays truthful. Unlike the old
CDS-seeded path (see app/providers/era5.py), `precipitation_sum` here is a
real daily total, not a 1-hour accumulation ending at a fixed hour.
"""

import logging
from dataclasses import dataclass

import httpx

logger = logging.getLogger(__name__)

ARCHIVE_BASE_URL = "https://archive-api.open-meteo.com/v1/archive"

_DAILY_FIELDS = (
    "temperature_2m_max,temperature_2m_min,temperature_2m_mean,"
    "precipitation_sum,windspeed_10m_max,winddirection_10m_dominant"
)


@dataclass
class ArchiveDayData:
    date: str
    temp_max_c: float | None
    temp_min_c: float | None
    temp_mean_c: float | None
    precip_sum_mm: float | None
    wind_speed_max_kmh: float | None
    wind_direction_dominant_deg: float | None


def _daily_at(daily: dict, field: str, index: int):
    """One optional daily value, or None if the field or index is missing.

    Every field requested here can still come back null for a given day
    (e.g. no dominant wind direction on a calm day), and a missing value
    must never be coerced to 0 or a dash — this product's one unacceptable
    failure is under-reporting.
    """
    values = daily.get(field)
    if not isinstance(values, list) or index >= len(values):
        return None
    return values[index]


class OpenMeteoArchiveProvider:
    """A reusable archive client.

    Deliberately NOT the close-inside-`finally` shape the other providers
    in this package use. Those are called once per request; this one is
    called twice — the requested day and the same day a year earlier — and
    closing after the first call made the second raise "Cannot send a
    request, as the client has been closed", surfacing as a bare 500.

    Nothing caught that, because every test injects its own client and so
    never exercises the owned-client path. Ownership now ends at `close()`
    or the context manager, never mid-use.
    """

    def __init__(self, base_url: str = ARCHIVE_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def close(self) -> None:
        """Close the client if this provider created it. Injected clients
        belong to the caller and are left alone."""
        if self._owns_client:
            self._client.close()

    def __enter__(self) -> "OpenMeteoArchiveProvider":
        return self

    def __exit__(self, *exc_info) -> None:
        self.close()

    def fetch_day(self, latitude: float, longitude: float, date_str: str) -> ArchiveDayData | None:
        """One day's archive reading for (latitude, longitude, date_str).

        Returns None if the upstream response has no data for that day
        (e.g. a date outside the archive's coverage) rather than raising —
        callers should still handle exceptions defensively for genuine
        request failures.

        Does NOT close the client — a provider is called twice per request
        (see the class docstring) and must stay usable across both calls.
        Call `close()` (or use this as a context manager) when done.
        """
        response = self._client.get(
            self._base_url,
            params={
                "latitude": latitude,
                "longitude": longitude,
                "start_date": date_str,
                "end_date": date_str,
                "daily": _DAILY_FIELDS,
                "timezone": "auto",
            },
        )
        response.raise_for_status()
        payload = response.json()
        try:
            daily = payload["daily"]
            times = daily.get("time")
            if not times:
                return None
            index = 0
            return ArchiveDayData(
                date=times[index],
                temp_max_c=_daily_at(daily, "temperature_2m_max", index),
                temp_min_c=_daily_at(daily, "temperature_2m_min", index),
                temp_mean_c=_daily_at(daily, "temperature_2m_mean", index),
                precip_sum_mm=_daily_at(daily, "precipitation_sum", index),
                wind_speed_max_kmh=_daily_at(daily, "windspeed_10m_max", index),
                wind_direction_dominant_deg=_daily_at(
                    daily, "winddirection_10m_dominant", index
                ),
            )
        except (KeyError, TypeError) as exc:
            logger.warning(
                "Failed to parse Open-Meteo archive response for (%s, %s, %s): %s",
                latitude,
                longitude,
                date_str,
                exc,
            )
            raise
