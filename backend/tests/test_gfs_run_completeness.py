"""A GFS cycle must not be selected until the hours we need exist.

NOAA publishes a cycle's forecast hours progressively — f000 within
minutes of the cycle time, f120 several hours later. Probing f000 alone
reports the cycle as available while its later hours are still missing,
and ingestion then 404s partway through. This is not hypothetical: it is
what happens for a few hours after every cycle, and it is how the live
`prime_demo` run failed on `gfs.20260910/00/.../f120.idx`.
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock

import httpx

from app.providers.gfs import NoaaGfsProvider


def _client_serving(available_keys: set[str]) -> MagicMock:
    """A client where only `available_keys` substrings resolve 200."""
    client = MagicMock()

    def _head(url, *args, **kwargs):
        for key in available_keys:
            if key in url:
                return httpx.Response(200, request=httpx.Request("HEAD", url))
        return httpx.Response(404, request=httpx.Request("HEAD", url))

    client.head.side_effect = _head
    return client


def test_skips_a_cycle_whose_later_hours_are_not_published(monkeypatch):
    # 05:00 UTC. Today's 00Z cycle has published f000 but not yet f120 —
    # the exact state that broke the live run.
    fixed_now = datetime(2026, 9, 10, 5, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)

    client = _client_serving({
        "gfs.20260910/00/atmos/gfs.t00z.pgrb2.0p25.f000",
        # Yesterday's 18Z is complete.
        "gfs.20260909/18/atmos/gfs.t18z.pgrb2.0p25.f000",
        "gfs.20260909/18/atmos/gfs.t18z.pgrb2.0p25.f120",
    })

    provider = NoaaGfsProvider(client=client)
    run_date, run_hour = provider.discover_latest_run(probe_forecast_hour=120)

    # Falls back to the complete previous cycle rather than picking the
    # newer one and failing later.
    assert (run_date, run_hour) == ("20260909", "18")


def test_selects_the_newest_cycle_once_it_is_complete(monkeypatch):
    fixed_now = datetime(2026, 9, 10, 5, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)

    client = _client_serving({
        "gfs.20260910/00/atmos/gfs.t00z.pgrb2.0p25.f120",
        "gfs.20260909/18/atmos/gfs.t18z.pgrb2.0p25.f120",
    })

    provider = NoaaGfsProvider(client=client)

    assert provider.discover_latest_run(probe_forecast_hour=120) == (
        "20260910",
        "00",
    )


def test_probes_the_requested_hour_not_f000(monkeypatch):
    # Guards the actual mechanism: with only f000 available anywhere, a
    # request for f120 must find nothing rather than happily returning a
    # cycle it cannot satisfy.
    fixed_now = datetime(2026, 9, 10, 5, 0, tzinfo=timezone.utc)
    monkeypatch.setattr("app.providers.gfs._utcnow", lambda: fixed_now)

    client = _client_serving({"pgrb2.0p25.f000"})
    provider = NoaaGfsProvider(client=client)

    try:
        provider.discover_latest_run(probe_forecast_hour=120)
        raise AssertionError("expected no usable cycle to be found")
    except RuntimeError:
        pass

    # And the URLs it probed really were f120, not f000.
    probed = [call.args[0] for call in client.head.call_args_list]
    assert probed, "nothing was probed"
    assert all("f120.idx" in url for url in probed), probed


def test_ingestion_probes_the_furthest_hour_it_will_fetch(monkeypatch):
    # The provider change is only useful if the caller passes the right
    # hour; this pins that wiring.
    from app.ingestion import gfs as gfs_ingestion

    seen: dict[str, int] = {}

    class _Provider:
        def discover_latest_run(self, probe_forecast_hour=0):
            seen["probe"] = probe_forecast_hour
            raise RuntimeError("stop here — discovery is all we are testing")

        def close(self):
            pass

    try:
        gfs_ingestion.ingest_gfs_forecast(
            provider=_Provider(), forecast_hours=[0, 24, 72]
        )
    except Exception:
        pass

    assert seen["probe"] == 72
