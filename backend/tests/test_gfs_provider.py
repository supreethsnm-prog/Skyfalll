import math
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock

import httpx
import numpy as np
import pytest
import xarray as xr

from app.providers.gfs import NoaaGfsProvider, _crop_to_india

FIXTURE = Path(__file__).parent / "fixtures" / "gfs_t2m_sample.grib2"


def _mock_client(head_responses: dict[str, int]) -> MagicMock:
    client = MagicMock()

    def _head(url, **kwargs):
        for key, status in head_responses.items():
            if key in url:
                return httpx.Response(
                    status_code=status, request=httpx.Request("HEAD", url)
                )
        return httpx.Response(status_code=404, request=httpx.Request("HEAD", url))

    client.head.side_effect = _head
    return client


def test_discover_latest_run_finds_newest_available_cycle(monkeypatch):
    fixed_now = datetime(2026, 9, 8, 5, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({"gfs.20260908/00": 200})

    provider = NoaaGfsProvider(client=client)
    run_date, run_hour = provider.discover_latest_run()

    assert (run_date, run_hour) == ("20260908", "00")


def test_discover_latest_run_falls_back_when_newest_cycle_not_yet_published(monkeypatch):
    # It's 13:00 UTC — the 12Z cycle would normally be expected, but hasn't
    # actually been published yet (confirmed live behavior: the newest cycle
    # can legitimately not exist).
    fixed_now = datetime(2026, 9, 8, 13, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({"gfs.20260908/06": 200})  # 12Z missing, 06Z exists

    provider = NoaaGfsProvider(client=client)
    run_date, run_hour = provider.discover_latest_run()

    assert (run_date, run_hour) == ("20260908", "06")


def test_discover_latest_run_falls_back_to_previous_day(monkeypatch):
    fixed_now = datetime(2026, 9, 8, 1, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({"gfs.20260907/18": 200})

    provider = NoaaGfsProvider(client=client)
    run_date, run_hour = provider.discover_latest_run()

    assert (run_date, run_hour) == ("20260907", "18")


def test_discover_latest_run_raises_when_nothing_found(monkeypatch):
    fixed_now = datetime(2026, 9, 8, 5, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({})  # nothing exists — every HEAD 404s

    provider = NoaaGfsProvider(client=client)
    with pytest.raises(RuntimeError, match="No recent GFS run"):
        provider.discover_latest_run()


def test_discover_latest_run_checks_the_f000_idx_key(monkeypatch):
    fixed_now = datetime(2026, 9, 8, 5, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)
    client = _mock_client({"gfs.20260908/00": 200})

    NoaaGfsProvider(client=client).discover_latest_run()

    checked = client.head.call_args_list[-1].args[0]
    assert checked == (
        "https://noaa-gfs-bdp-pds.s3.amazonaws.com/"
        "gfs.20260908/00/atmos/gfs.t00z.pgrb2.0p25.f000.idx"
    )


def test_byte_range_for_uses_the_next_messages_offset_as_the_end():
    idx = (
        "1:0:d=2026090718:PRMSL:mean sea level:anl:\n"
        "2:1001597:d=2026090718:CLMR:1 hybrid level:anl:\n"
        "3:1097283:d=2026090718:ICMR:1 hybrid level:anl:\n"
    )
    provider = NoaaGfsProvider(client=MagicMock())

    assert provider._byte_range_for(idx, "PRMSL", "mean sea level") == (0, 1001597)
    assert provider._byte_range_for(idx, "CLMR", "1 hybrid level") == (1001597, 1097283)
    # The final message has no successor, so its range is open-ended.
    assert provider._byte_range_for(idx, "ICMR", "1 hybrid level") == (1097283, None)

    with pytest.raises(ValueError, match="not found"):
        provider._byte_range_for(idx, "TMP", "2 m above ground")


def test_byte_range_for_prefers_the_instantaneous_message_over_a_period_average():
    # Real f024 index shape: PRATE and TCDC each appear twice, once
    # instantaneous and once averaged over the preceding 6 hours. Every
    # other field in a row is instantaneous, so the instantaneous variant is
    # the one that belongs with them.
    idx = (
        "1:0:d=2026090718:PRATE:surface:18-24 hour ave fcst:\n"
        "2:1000:d=2026090718:PRATE:surface:24 hour fcst:\n"
        "3:2000:d=2026090718:TCDC:entire atmosphere:24 hour fcst:\n"
        "4:3000:d=2026090718:TCDC:entire atmosphere:18-24 hour ave fcst:\n"
        "5:4000:d=2026090718:TMP:2 m above ground:24 hour fcst:\n"
    )
    provider = NoaaGfsProvider(client=MagicMock())

    # Averaged variant listed first — still picks the instantaneous one.
    assert provider._byte_range_for(idx, "PRATE", "surface") == (1000, 2000)
    # Instantaneous listed first — unchanged.
    assert provider._byte_range_for(idx, "TCDC", "entire atmosphere") == (2000, 3000)


def test_committed_fixture_opens_and_yields_a_sane_temperature():
    # Confirms the checked-in fixture is genuinely valid GRIB2 and that
    # cfgrib's heightAboveGround/level=2 filter actually isolates it —
    # this is the one live-verified fact this whole task is built on.
    with xr.open_dataset(
        FIXTURE,
        engine="cfgrib",
        filter_by_keys={"typeOfLevel": "heightAboveGround", "level": 2},
        indexpath="",
    ) as ds:
        mumbai_temp_k = ds["t2m"].sel(
            latitude=19.0, longitude=73.0, method="nearest"
        ).values
        assert 260 < float(mumbai_temp_k) < 320  # sane Kelvin for a surface temp


def test_crop_to_india_yields_the_expected_0p25_degree_grid():
    # The global 0.25-degree grid is latitude 90 -> -90 DESCENDING and
    # longitude 0 -> 359.75 ascending; India's box is 129 x 121 = 15,609 points.
    with xr.open_dataset(
        FIXTURE,
        engine="cfgrib",
        filter_by_keys={"typeOfLevel": "heightAboveGround", "level": 2},
        indexpath="",
    ) as ds:
        assert float(ds["latitude"].values[0]) == 90.0
        assert float(ds["latitude"].values[-1]) == -90.0

        cropped = _crop_to_india(ds)
        lats = cropped["latitude"].values
        lons = cropped["longitude"].values

    assert (float(lats[0]), float(lats[-1])) == (38.0, 6.0)
    assert (float(lons[0]), float(lons[-1])) == (68.0, 98.0)
    assert len(lats) * len(lons) == 15609


def test_close_only_closes_a_client_it_owns():
    injected = MagicMock()
    NoaaGfsProvider(client=injected).close()
    injected.close.assert_not_called()

    owning = NoaaGfsProvider()
    owning.close()
    assert owning._client.is_closed


# --- fetch_india_grid's numeric transform layer -----------------------------
#
# The rest of this file exercises fetch_india_grid's unit-conversion and
# wind-vector math entirely offline: _fetch_field_group (which does the real
# network fetch + cfgrib parse) is monkeypatched to hand back small,
# hand-built xr.Dataset objects shaped like real cfgrib output (a
# "latitude"/"longitude"-dimensioned Dataset with the field-group's cfgrib
# variable names), so fetch_india_grid's own arithmetic is what's under test.


def _fake_dataset(field_values: dict, lat, lon) -> xr.Dataset:
    data_vars = {
        name: (("latitude", "longitude"), np.asarray(values, dtype=float))
        for name, values in field_values.items()
    }
    coords = {
        "latitude": np.asarray(lat, dtype=float),
        "longitude": np.asarray(lon, dtype=float),
    }
    return xr.Dataset(data_vars, coords=coords)


def _provider_with_fake_fields(
    monkeypatch, field_values: dict, lat=(20.0, 10.0), lon=(70.0, 80.0)
) -> NoaaGfsProvider:
    """A provider whose _fetch_idx/_fetch_field_group never touch the network.

    field_values maps a cfgrib variable name (e.g. "t2m", "u10") to a 2D
    array shaped (len(lat), len(lon)). Only the field groups that have at
    least one requested variable produce a fake Dataset; the rest report
    "field missing" (None), exactly like the real fetch does when a field
    isn't present at a forecast hour.
    """
    provider = NoaaGfsProvider(client=MagicMock())
    monkeypatch.setattr(provider, "_fetch_idx", lambda *a, **k: "")

    def fake_fetch_field_group(run_date, run_hour, forecast_hour, idx_text, group):
        group_vars = {
            field.var_name: field_values[field.var_name]
            for field in group.fields
            if field.var_name in field_values
        }
        if not group_vars:
            return None
        return _fake_dataset(group_vars, lat, lon)

    monkeypatch.setattr(provider, "_fetch_field_group", fake_fetch_field_group)
    return provider


def test_fetch_india_grid_converts_kelvin_to_celsius(monkeypatch):
    provider = _provider_with_fake_fields(
        monkeypatch, {"t2m": np.full((2, 2), 300.0)}
    )

    results = provider.fetch_india_grid("20260908", "00", 0)

    assert len(results) == 4
    assert results[0].temp_2m_c == pytest.approx(26.85)
    assert all(r.temp_2m_c == pytest.approx(26.85) for r in results)


def test_fetch_india_grid_converts_wind_gust_ms_to_kmh(monkeypatch):
    # Flagged by review: this * 3.6 conversion is easy to accidentally drop.
    provider = _provider_with_fake_fields(
        monkeypatch, {"gust": np.full((2, 2), 5.0)}
    )

    results = provider.fetch_india_grid("20260908", "00", 0)

    assert all(r.wind_gust_kmh == pytest.approx(18.0) for r in results)


def test_fetch_india_grid_converts_precip_rate_to_mm_per_hour(monkeypatch):
    provider = _provider_with_fake_fields(
        monkeypatch, {"prate": np.full((2, 2), 0.001)}
    )

    results = provider.fetch_india_grid("20260908", "00", 0)

    # 1 kg/m^2/s == 1 mm/s of water depth -> * 3600 s/h.
    assert all(r.precip_rate_mmh == pytest.approx(3.6) for r in results)


def test_fetch_india_grid_converts_pa_to_hpa(monkeypatch):
    provider = _provider_with_fake_fields(
        monkeypatch, {"prmsl": np.full((2, 2), 101325.0)}
    )

    results = provider.fetch_india_grid("20260908", "00", 0)

    assert all(r.mslp_hpa == pytest.approx(1013.25) for r in results)


def test_fetch_india_grid_computes_wind_speed_and_direction_from_uv(monkeypatch):
    # Two grid points at the same latitude, differing only in u10's sign, so
    # the two produce different "from" directions with identical speed. The
    # second latitude row is unused filler — a single-row coordinate confuses
    # xarray's monotonic-direction inference for _crop_to_india's slice.
    u10 = np.array([[1.0, -1.0], [0.0, 0.0]])
    v10 = np.array([[1.0, 1.0], [0.0, 0.0]])
    provider = _provider_with_fake_fields(monkeypatch, {"u10": u10, "v10": v10})

    results = provider.fetch_india_grid("20260908", "00", 0)

    assert len(results) == 4
    point_a, point_b = results[0], results[1]  # (lat=20, lon=70), (lat=20, lon=80)

    expected_speed_a = math.hypot(1.0, 1.0) * 3.6
    expected_dir_a = math.degrees(math.atan2(-1.0, -1.0)) % 360.0
    assert point_a.wind_speed_10m_kmh == pytest.approx(expected_speed_a)
    assert point_a.wind_direction_10m_deg == pytest.approx(expected_dir_a)
    assert expected_dir_a == pytest.approx(225.0)  # from the south-west

    expected_speed_b = math.hypot(-1.0, 1.0) * 3.6
    expected_dir_b = math.degrees(math.atan2(1.0, -1.0)) % 360.0
    assert point_b.wind_speed_10m_kmh == pytest.approx(expected_speed_b)
    assert point_b.wind_direction_10m_deg == pytest.approx(expected_dir_b)
    assert expected_dir_b == pytest.approx(135.0)  # from the north-west

    # Same magnitude, genuinely different directions.
    assert point_a.wind_speed_10m_kmh == pytest.approx(point_b.wind_speed_10m_kmh)
    assert point_a.wind_direction_10m_deg != pytest.approx(
        point_b.wind_direction_10m_deg
    )


def test_fetch_india_grid_maps_masked_nan_values_to_none(monkeypatch):
    # A GRIB bitmap-masked point comes back as NaN from cfgrib — it must
    # surface as None, not as a float NaN, on the output dataclass. The
    # second latitude row is unused filler (see the wind test above for why
    # a single-row coordinate is avoided).
    provider = _provider_with_fake_fields(
        monkeypatch,
        {"t2m": np.array([[300.0, float("nan")], [300.0, 300.0]])},
    )

    results = provider.fetch_india_grid("20260908", "00", 0)

    assert len(results) == 4
    assert results[0].temp_2m_c == pytest.approx(26.85)  # (lat=20, lon=70)
    assert results[1].temp_2m_c is None  # (lat=20, lon=80) — masked
