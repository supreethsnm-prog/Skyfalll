from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock

import httpx
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
