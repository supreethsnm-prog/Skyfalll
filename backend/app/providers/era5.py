"""CDS/ERA5 provider: fetches one (location, date) reading from the
Copernicus Climate Data Store's ERA5 reanalysis dataset.

Built from live research against the real API, not assumed:

* **The response shape is inconsistent.** A request for several variables
  comes back as a ZIP archive of *two* NetCDF files — ERA5 splits by GRIB
  `stepType`, so instantaneous fields (`t2m`, `d2m`, `u10`, `v10`, `msl`)
  land in `data_stream-oper_stepType-instant.nc` and accumulated fields
  (`tp`) in `data_stream-oper_stepType-accum.nc`. A single-variable (or
  single-stepType) request comes back as one plain NetCDF file. The
  archive is *not* named `.zip` — CDS hands back whatever target name you
  gave it — so sniff with `zipfile.is_zipfile()` rather than trusting the
  extension. `_parse_response` handles both shapes.
* **Units are SI-raw**: `t2m`/`d2m` in kelvin, `msl` in pascals, `tp` in
  metres of water equivalent, `u10`/`v10` in m/s. All converted below.
* **`area` is `[north, west, south, east]`** and snaps to ERA5's 0.25°
  grid, so a small box around the point always yields real grid points.

Deliberately synchronous and blocking (unlike every other provider in this
codebase) — this is only ever called from a standalone seed script a human
runs once, never from a request handler or a scheduled job. A real call
takes 25 seconds to 2 minutes.
"""

import math
import os
import tempfile
import zipfile

import xarray as xr

from app.providers.historical import Era5ReadingData

CDS_DATASET_ID = "reanalysis-era5-single-levels"
CDS_URL = "https://cds.climate.copernicus.eu/api"

_VARIABLES = [
    "2m_temperature",
    "2m_dewpoint_temperature",
    "total_precipitation",
    "10m_u_component_of_wind",
    "10m_v_component_of_wind",
    "mean_sea_level_pressure",
]

# A generous box around the requested point — large enough that the
# nearest-grid-point lookup below always has real data to select from,
# small enough to stay well clear of CDS's large-area deprioritization
# (confirmed live: ~1 degree boxes return in the same latency range as a
# single point).
_BOX_HALF_DEGREES = 0.5

# ERA5 reanalysis is hourly; we take one representative daily snapshot
# rather than fetching 24 fields per (city, day).
_OBSERVATION_TIME = "12:00"

_MISSING_KEY_MESSAGE = (
    "CDS_API_KEY is not set. Register at https://cds.climate.copernicus.eu, "
    "generate a key, and accept the Terms of Use for "
    "'reanalysis-era5-single-levels' on that dataset's own page before "
    "setting CDS_API_KEY in backend/.env."
)


def _clean(value) -> float | None:
    v = float(value)
    return v if math.isfinite(v) else None


class CdsEra5Provider:
    """Client is constructed lazily, on the first `fetch_reading` call.

    Construction is deferred (rather than done in `__init__`) so that
    parsing-only use — the fixture-based tests, and anything that wants to
    re-read an already-downloaded response — needs neither a CDS API key
    nor the `ecmwf.datastores` import. Any real fetch still requires both.
    """

    def __init__(self, client=None, api_key: str | None = None):
        self._client = client
        self._api_key = api_key

    def _ensure_client(self):
        if self._client is None:
            import ecmwf.datastores as eds

            from app.config import get_settings

            key = self._api_key if self._api_key is not None else get_settings().cds_api_key
            if not key:
                raise ValueError(_MISSING_KEY_MESSAGE)
            self._client = eds.Client(url=CDS_URL, key=key)
        return self._client

    def fetch_reading(
        self, location_name: str, latitude: float, longitude: float, observation_date: str
    ) -> Era5ReadingData | None:
        year, month, day = observation_date.split("-")
        request = {
            "product_type": "reanalysis",
            "variable": _VARIABLES,
            "year": year,
            "month": month,
            "day": day,
            "time": _OBSERVATION_TIME,
            "area": [
                latitude + _BOX_HALF_DEGREES,
                longitude - _BOX_HALF_DEGREES,
                latitude - _BOX_HALF_DEGREES,
                longitude + _BOX_HALF_DEGREES,
            ],
            "data_format": "netcdf",
        }
        client = self._ensure_client()
        with tempfile.TemporaryDirectory() as tmp:
            target = os.path.join(tmp, "era5_response")
            client.retrieve(CDS_DATASET_ID, request, target=target)
            return self._parse_response(
                target, location_name, latitude, longitude, observation_date
            )

    def _parse_response(
        self, path: str, location_name: str, latitude: float, longitude: float, observation_date: str
    ) -> Era5ReadingData:
        if zipfile.is_zipfile(path):
            extract_dir = tempfile.mkdtemp()
            with zipfile.ZipFile(path) as z:
                z.extractall(extract_dir)
            members = [
                os.path.join(extract_dir, name) for name in sorted(os.listdir(extract_dir))
            ]
        else:
            extract_dir = None
            members = [path]

        try:
            merged = self._load_and_merge(members)
        finally:
            if extract_dir is not None:
                # Best-effort: on Windows a lingering HDF5 handle can keep a
                # member locked, and a stale temp file is not worth failing a
                # parse over.
                import shutil

                shutil.rmtree(extract_dir, ignore_errors=True)

        point = merged.sel(latitude=latitude, longitude=longitude, method="nearest")

        def _var(name: str) -> float | None:
            if name not in point:
                return None
            return _clean(point[name].values[0])

        t2m_k = _var("t2m")
        d2m_k = _var("d2m")
        u10 = _var("u10")
        v10 = _var("v10")
        msl_pa = _var("msl")
        tp_m = _var("tp")

        wind_speed_kmh = wind_direction_deg = None
        if u10 is not None and v10 is not None:
            # 1 m/s == 3.6 km/h. Direction is the meteorological convention
            # (degrees clockwise from north that the wind blows *from*),
            # which is why both components are negated before atan2.
            wind_speed_kmh = math.hypot(u10, v10) * 3.6
            wind_direction_deg = math.degrees(math.atan2(-u10, -v10)) % 360

        return Era5ReadingData(
            location_name=location_name,
            latitude=latitude,
            longitude=longitude,
            observation_date=observation_date,
            temp_2m_c=(t2m_k - 273.15) if t2m_k is not None else None,
            dewpoint_2m_c=(d2m_k - 273.15) if d2m_k is not None else None,
            precip_mm=(tp_m * 1000) if tp_m is not None else None,
            wind_speed_10m_kmh=wind_speed_kmh,
            wind_direction_10m_deg=wind_direction_deg,
            mslp_hpa=(msl_pa / 100) if msl_pa is not None else None,
        )

    @staticmethod
    def _load_and_merge(member_paths: list[str]) -> xr.Dataset:
        """Read every NetCDF member fully into memory and close its handle.

        `.load()` pulls the (tiny — a handful of 4x4 grids) arrays into
        memory so the file handle can be released immediately; on Windows a
        still-open HDF5 handle would otherwise block cleanup of the
        extraction directory.
        """
        datasets = []
        for member in member_paths:
            with xr.open_dataset(member, engine="h5netcdf") as ds:
                datasets.append(ds.load())
        return xr.merge(datasets, compat="override")

    def close(self) -> None:
        pass  # ecmwf.datastores.Client has no explicit close/session to release
