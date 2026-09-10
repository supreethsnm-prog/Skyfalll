"""NOAA GFS provider: discovers the latest published model run on the
public, unauthenticated S3 bucket noaa-gfs-bdp-pds, fetches a handful of
surface fields cropped to India via HTTP Range GET (never downloading a
whole ~480MB global file), and parses them with cfgrib/xarray.

Every fact this module depends on was confirmed against the live bucket
during implementation, not assumed:

* Object key layout: ``gfs.<YYYYMMDD>/<HH>/atmos/gfs.t<HH>z.pgrb2.0p25.f<FFF>``
  with a sibling ``.idx`` text index. A HEAD on the ``.idx`` key returns 200
  when the cycle is published and 404 when it is not — the newest synoptic
  cycle can legitimately not exist yet, so discovery walks backwards.
* ``.idx`` line format: ``<n>:<byte offset>:d=<YYYYMMDDHH>:<PARAM>:<LEVEL>:<time range>:``
  A message's byte range is ``[its offset, next line's offset)``; the last
  message runs to end-of-file. GRIB2 messages are self-delimiting, so the
  concatenation of several messages' byte ranges is itself a valid, directly
  cfgrib-openable multi-message GRIB2 file.
* Grid orientation: latitude runs 90.0 -> -90.0 (DESCENDING, 721 points) and
  longitude runs 0.0 -> 359.75 (ascending, 1440 points) at 0.25 degrees. The
  descending latitude axis is why ``_crop_to_india`` slices lat high-to-low.
  India's box yields 129 x 121 = 15,609 grid points.
* cfgrib ``typeOfLevel`` / variable names per field group: see ``_FIELD_GROUPS``
  below, where each group records the observed values.
"""

import logging
import math
import os
import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import httpx
import numpy as np
import xarray as xr

from app.providers.nwp import GfsGridPointData
from app.providers.retry import call_with_retries

logger = logging.getLogger(__name__)

GFS_BASE_URL = "https://noaa-gfs-bdp-pds.s3.amazonaws.com"

_SYNOPTIC_HOURS = ("18", "12", "06", "00")  # newest-first within a day
_INDIA_LAT_RANGE = (6.0, 38.0)
_INDIA_LON_RANGE = (68.0, 98.0)

_MS_TO_KMH = 3.6
_KELVIN_OFFSET = 273.15
_SECONDS_PER_HOUR = 3600.0
_PA_PER_HPA = 100.0


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _run_key(run_date: str, run_hour: str, forecast_hour: int) -> str:
    return (
        f"gfs.{run_date}/{run_hour}/atmos/"
        f"gfs.t{run_hour}z.pgrb2.0p25.f{forecast_hour:03d}"
    )


@dataclass(frozen=True)
class _GfsField:
    """One GRIB2 message to pull, and where its value lands.

    ``idx_param``/``idx_level`` are matched against fields 4 and 5 of an
    ``.idx`` line to locate the message's byte range. ``var_name`` is the
    variable name cfgrib actually assigns once the message is parsed —
    hardcoded from live observation rather than fuzzy-matched, because
    cfgrib's short names do not follow the GRIB param names mechanically
    (``TMP`` -> ``t2m``, ``RH`` -> ``r2``, ``TCDC`` -> ``tcc``).
    """

    idx_param: str
    idx_level: str
    var_name: str
    attr_name: str


@dataclass(frozen=True)
class _FieldGroup:
    filter_by_keys: dict
    fields: tuple[_GfsField, ...]


# All five groups' filter_by_keys and cfgrib variable names were verified
# live against gfs.20260907/18 f000 on the real bucket. Notably TCDC's
# "entire atmosphere" level resolves to typeOfLevel "atmosphere" (NOT
# "atmosphereSingleLayer"), and cfgrib names the variable "tcc".
_FIELD_GROUPS: tuple[_FieldGroup, ...] = (
    _FieldGroup(
        filter_by_keys={"typeOfLevel": "heightAboveGround", "level": 2},
        fields=(
            _GfsField("TMP", "2 m above ground", "t2m", "temp_2m_c"),  # K
            _GfsField("RH", "2 m above ground", "r2", "relative_humidity_2m_pct"),  # %
        ),
    ),
    _FieldGroup(
        filter_by_keys={"typeOfLevel": "heightAboveGround", "level": 10},
        fields=(
            _GfsField("UGRD", "10 m above ground", "u10", "_u10"),  # m/s
            _GfsField("VGRD", "10 m above ground", "v10", "_v10"),  # m/s
        ),
    ),
    _FieldGroup(
        filter_by_keys={"typeOfLevel": "surface"},
        fields=(
            _GfsField("GUST", "surface", "gust", "wind_gust_kmh"),  # m/s
            _GfsField("PRATE", "surface", "prate", "precip_rate_mmh"),  # kg/m^2/s
            _GfsField("CAPE", "surface", "cape", "cape_j_per_kg"),  # J/kg
            _GfsField("CIN", "surface", "cin", "cin_j_per_kg"),  # J/kg
        ),
    ),
    _FieldGroup(
        filter_by_keys={"typeOfLevel": "meanSea"},
        fields=(_GfsField("PRMSL", "mean sea level", "prmsl", "_mslp_pa"),),  # Pa
    ),
    _FieldGroup(
        filter_by_keys={"typeOfLevel": "atmosphere"},
        fields=(_GfsField("TCDC", "entire atmosphere", "tcc", "cloud_cover_pct"),),  # %
    ),
)


def _crop_to_india(ds: xr.Dataset) -> xr.Dataset:
    # Latitude is stored DESCENDING (90 -> -90), so the slice runs high-to-low.
    return ds.sel(
        latitude=slice(_INDIA_LAT_RANGE[1], _INDIA_LAT_RANGE[0]),
        longitude=slice(_INDIA_LON_RANGE[0], _INDIA_LON_RANGE[1]),
    )


def _clean(value: float) -> float | None:
    """GRIB bitmap-masked points come back as NaN — store them as NULL.

    Checks isfinite rather than isnan so ±inf is mapped to NULL too: not
    reachable from real GRIB2 data today, but an inf reaching a response
    would raise in Starlette's JSONResponse (allow_nan=False) and surface
    as an HTTP 500 on /nwp instead of a clean null.
    """
    return None if not math.isfinite(value) else value


class NoaaGfsProvider:
    def __init__(self, client: httpx.Client | None = None):
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=60.0)

    def discover_latest_run(self, probe_forecast_hour: int = 0) -> tuple[str, str]:
        """Return the (run_date, run_hour) of the newest usable GFS cycle.

        Walks today's already-elapsed synoptic hours newest-first, then all of
        yesterday's, HEAD-ing each candidate's ``.idx`` key. The newest
        elapsed cycle is frequently not published yet (GFS lags its cycle time
        by a few hours), so a 404 here is normal, not an error.

        [probe_forecast_hour] is which forecast hour to probe, and it must be
        the LAST hour the caller intends to fetch — not the default 0.

        NOAA publishes a cycle's forecast hours PROGRESSIVELY: f000 appears
        within minutes, f120 several hours later. Probing f000 therefore
        reports a cycle as available while its later hours are still missing,
        and the caller then 404s partway through ingestion. That is not a
        hypothetical — it is what happens for a few hours after every cycle,
        i.e. much of the day. Probing the last hour instead means a cycle is
        only selected once it can actually satisfy the whole request, and an
        incomplete newest cycle falls back to the previous one, which is
        exactly the behaviour the fallback list already provides.
        """
        now = _utcnow()
        candidates: list[tuple[str, str]] = []
        for hour in _SYNOPTIC_HOURS:
            if int(hour) <= now.hour:
                candidates.append((now.strftime("%Y%m%d"), hour))
        yesterday = now - timedelta(days=1)
        for hour in _SYNOPTIC_HOURS:
            candidates.append((yesterday.strftime("%Y%m%d"), hour))

        for run_date, run_hour in candidates:
            idx_url = (
                f"{GFS_BASE_URL}/"
                f"{_run_key(run_date, run_hour, probe_forecast_hour)}.idx"
            )
            try:
                response = call_with_retries(lambda url=idx_url: self._client.head(url))
            except httpx.HTTPStatusError as exc:
                if exc.response.status_code in (403, 404):
                    continue  # cycle not published (yet) — try the next-oldest
                raise
            if response.status_code == 200:
                return run_date, run_hour

        raise RuntimeError(
            "No recent GFS run found in the last two days of synoptic cycles"
        )

    def _fetch_idx(self, run_date: str, run_hour: str, forecast_hour: int) -> str:
        idx_url = f"{GFS_BASE_URL}/{_run_key(run_date, run_hour, forecast_hour)}.idx"
        response = call_with_retries(lambda: self._client.get(idx_url))
        return response.text

    def _byte_range_for(
        self, idx_text: str, param: str, level_text: str
    ) -> tuple[int, int | None]:
        """Locate one message's ``[start, end)`` byte range in the ``.idx``.

        A param:level pair is not necessarily unique. At forecast hours > 0
        the real index carries BOTH an instantaneous and a period-aggregated
        message for some fields — e.g. f024 has
        ``PRATE:surface:24 hour fcst`` and
        ``PRATE:surface:18-24 hour ave fcst`` (likewise TCDC). We want the
        instantaneous value, since every other field in the row is
        instantaneous and the row is stamped with a single ``valid_time``.
        An aggregated message is identifiable by its time-range descriptor
        starting with a span (``18-24 hour ...``) rather than a single
        instant (``anl`` / ``24 hour fcst``).
        """
        lines = idx_text.strip().splitlines()
        starts = [int(line.split(":")[1]) for line in lines]

        matches: list[int] = []
        for i, line in enumerate(lines):
            parts = line.split(":")
            if parts[3] == param and parts[4] == level_text:
                matches.append(i)

        if not matches:
            raise ValueError(
                f"Field '{param}:{level_text}' not found in this forecast hour's index"
            )

        chosen = matches[0]
        for i in matches:
            time_range = lines[i].split(":")[5]
            if "-" not in time_range.split(" ", 1)[0]:
                chosen = i
                break

        start = starts[chosen]
        end = starts[chosen + 1] if chosen + 1 < len(starts) else None
        return start, end

    def _fetch_field_group(
        self,
        run_date: str,
        run_hour: str,
        forecast_hour: int,
        idx_text: str,
        group: _FieldGroup,
    ) -> xr.Dataset | None:
        # Fetch every field in this group's byte ranges and concatenate — a
        # cfgrib-openable multi-message file is just the concatenation of
        # each message's own bytes (GRIB2 messages are self-delimiting).
        grib_url = f"{GFS_BASE_URL}/{_run_key(run_date, run_hour, forecast_hour)}"
        chunks: list[bytes] = []
        for field in group.fields:
            try:
                start, end = self._byte_range_for(
                    idx_text, field.idx_param, field.idx_level
                )
            except ValueError:
                # Field absent at this forecast hour — skip it, not fatal
                # (the storage columns are all nullable).
                logger.warning(
                    "GFS field %s:%s missing from %s %sz f%03d index",
                    field.idx_param,
                    field.idx_level,
                    run_date,
                    run_hour,
                    forecast_hour,
                )
                continue
            range_header = (
                f"bytes={start}-{end - 1}" if end is not None else f"bytes={start}-"
            )
            response = call_with_retries(
                lambda u=grib_url, h=range_header: self._client.get(
                    u, headers={"Range": h}
                )
            )
            chunks.append(response.content)

        if not chunks:
            return None

        with tempfile.NamedTemporaryFile(suffix=".grib2", delete=False) as tmp:
            tmp.write(b"".join(chunks))
            tmp_path = tmp.name
        try:
            # indexpath="" suppresses cfgrib's on-disk sidecar index, which
            # would otherwise be left behind next to the temp file. The
            # dataset is materialised before the temp file is unlinked
            # because eccodes reads lazily and Windows refuses to delete a
            # file that is still open.
            with xr.open_dataset(
                tmp_path,
                engine="cfgrib",
                filter_by_keys=group.filter_by_keys,
                indexpath="",
            ) as ds:
                return ds.load()
        finally:
            try:
                os.unlink(tmp_path)
            except OSError:  # pragma: no cover - best-effort cleanup
                logger.warning("Could not remove temporary GRIB file %s", tmp_path)

    def fetch_india_grid(
        self, run_date: str, run_hour: str, forecast_hour: int
    ) -> list[GfsGridPointData]:
        idx_text = self._fetch_idx(run_date, run_hour, forecast_hour)
        valid_time = datetime.strptime(run_date + run_hour, "%Y%m%d%H").replace(
            tzinfo=timezone.utc
        ) + timedelta(hours=forecast_hour)

        lats: np.ndarray | None = None
        lons: np.ndarray | None = None
        # attr name -> 2D (lat, lon) array cropped to India.
        planes: dict[str, np.ndarray] = {}

        for group in _FIELD_GROUPS:
            ds = self._fetch_field_group(
                run_date, run_hour, forecast_hour, idx_text, group
            )
            if ds is None:
                continue
            ds = _crop_to_india(ds)
            if lats is None:
                lats = ds["latitude"].values
                lons = ds["longitude"].values
            for field in group.fields:
                if field.var_name not in ds.data_vars:
                    logger.warning(
                        "GFS variable %r absent from group %r after parsing",
                        field.var_name,
                        group.filter_by_keys,
                    )
                    continue
                planes[field.attr_name] = np.asarray(
                    ds[field.var_name].values, dtype=float
                )

        if lats is None or lons is None:
            return []

        u10 = planes.get("_u10")
        v10 = planes.get("_v10")
        if u10 is not None and v10 is not None:
            planes["wind_speed_10m_kmh"] = np.hypot(u10, v10) * _MS_TO_KMH
            # Meteorological "direction the wind blows FROM", degrees clockwise
            # from north.
            planes["wind_direction_10m_deg"] = (
                np.degrees(np.arctan2(-u10, -v10)) % 360.0
            )
        planes.pop("_u10", None)
        planes.pop("_v10", None)

        if "temp_2m_c" in planes:
            planes["temp_2m_c"] = planes["temp_2m_c"] - _KELVIN_OFFSET  # K -> C
        if "wind_gust_kmh" in planes:
            planes["wind_gust_kmh"] = planes["wind_gust_kmh"] * _MS_TO_KMH  # m/s -> km/h
        if "precip_rate_mmh" in planes:
            # kg/m^2/s -> mm/h (1 kg/m^2 of water == 1 mm depth).
            planes["precip_rate_mmh"] = planes["precip_rate_mmh"] * _SECONDS_PER_HOUR
        if "_mslp_pa" in planes:
            planes["mslp_hpa"] = planes.pop("_mslp_pa") / _PA_PER_HPA

        # .tolist() converts once in C rather than paying float() per point.
        columns = {name: plane.tolist() for name, plane in planes.items()}
        lat_list = [float(v) for v in lats]
        lon_list = [float(v) for v in lons]

        results: list[GfsGridPointData] = []
        for i, lat in enumerate(lat_list):
            rows = {name: column[i] for name, column in columns.items()}
            for j, lon in enumerate(lon_list):

                def value(name: str, _j: int = j) -> float | None:
                    row = rows.get(name)
                    return None if row is None else _clean(row[_j])

                results.append(
                    GfsGridPointData(
                        run_date=run_date,
                        run_hour=run_hour,
                        forecast_hour=forecast_hour,
                        valid_time=valid_time,
                        grid_latitude=lat,
                        grid_longitude=lon,
                        temp_2m_c=value("temp_2m_c"),
                        relative_humidity_2m_pct=value("relative_humidity_2m_pct"),
                        wind_speed_10m_kmh=value("wind_speed_10m_kmh"),
                        wind_direction_10m_deg=value("wind_direction_10m_deg"),
                        wind_gust_kmh=value("wind_gust_kmh"),
                        precip_rate_mmh=value("precip_rate_mmh"),
                        cape_j_per_kg=value("cape_j_per_kg"),
                        cin_j_per_kg=value("cin_j_per_kg"),
                        cloud_cover_pct=value("cloud_cover_pct"),
                        mslp_hpa=value("mslp_hpa"),
                    )
                )
        return results

    def close(self) -> None:
        if self._owns_client:
            self._client.close()
