"""Tests for main.py's lifespan wiring of IngestionScheduler.

CRITICAL: none of these tests may let a real IngestionScheduler.start() run
to completion with a real network-hitting job function — see the plan's
Global Constraints. Every test here monkeypatches IngestionScheduler.start/
stop themselves (never lets a real thread spawn) or explicitly confirms
start was NOT called at all.

app.main.lifespan is an async context manager (FastAPI/Starlette's
lifespan= parameter requires one — verified directly: a plain
@contextmanager raises "TypeError: '_GeneratorContextManager' object does
not support the asynchronous context manager protocol" the moment
TestClient tries to `async with` it). These tests drive it with a small
`asyncio.run()` wrapper rather than pytest-asyncio, since nothing else in
this synchronous-everywhere codebase needs a pytest-asyncio dependency for
just this one file.
"""

import asyncio
from unittest.mock import MagicMock

from app.config import get_settings
from app.main import lifespan, app


def _run_lifespan_once():
    async def _run():
        async with lifespan(app):
            pass

    asyncio.run(_run())


def test_scheduler_defaults_to_disabled():
    assert get_settings().enable_scheduler is False


def test_lifespan_does_not_start_scheduler_when_disabled(monkeypatch):
    monkeypatch.setenv("ENABLE_SCHEDULER", "false")
    get_settings.cache_clear()
    mock_start = MagicMock()
    monkeypatch.setattr("app.main.IngestionScheduler.start", mock_start)

    try:
        _run_lifespan_once()

        mock_start.assert_not_called()
    finally:
        get_settings.cache_clear()


def test_lifespan_starts_scheduler_when_enabled(monkeypatch):
    monkeypatch.setenv("ENABLE_SCHEDULER", "true")
    get_settings.cache_clear()
    mock_start = MagicMock()
    mock_stop = MagicMock()
    monkeypatch.setattr("app.main.IngestionScheduler.start", mock_start)
    monkeypatch.setattr("app.main.IngestionScheduler.stop", mock_stop)

    try:
        _run_lifespan_once()

        mock_start.assert_called_once()
        jobs = mock_start.call_args[0][0]
        job_names = {job[0] for job in jobs}
        assert job_names == {"alerts", "marine", "gfs"}
        mock_stop.assert_called_once()
    finally:
        get_settings.cache_clear()


def test_lifespan_alerts_job_passes_the_broadcaster_to_ingest_alerts(monkeypatch):
    # The tests above only assert job NAMES and INTERVALS — they never invoke
    # the alerts job's lambda, so nothing here previously protected the wiring
    # that makes a SCHEDULED (as opposed to manually-triggered) ingestion push
    # to WebSocket clients. Deleting `on_new_alerts=...` from that lambda left
    # the whole suite green. This test closes that gap by actually calling the
    # job and asserting the real broadcaster reaches ingest_alerts.
    monkeypatch.setenv("ENABLE_SCHEDULER", "true")
    get_settings.cache_clear()
    mock_start = MagicMock()
    monkeypatch.setattr("app.main.IngestionScheduler.start", mock_start)
    monkeypatch.setattr("app.main.IngestionScheduler.stop", MagicMock())
    # The job constructs a real provider; stub it so invoking the lambda can
    # never touch the network (see this module's CRITICAL docstring note).
    monkeypatch.setattr("app.main.SACHETWarningProvider", MagicMock())
    seen = {}

    def _fake_ingest_alerts(provider, on_new_alerts=None):
        seen["cb"] = on_new_alerts
        return 0

    monkeypatch.setattr("app.main.ingest_alerts", _fake_ingest_alerts)

    try:
        _run_lifespan_once()

        jobs = mock_start.call_args[0][0]
        alerts_job = next(fn for name, fn, _interval in jobs if name == "alerts")
        alerts_job()

        assert "cb" in seen  # the lambda really did call ingest_alerts
        assert seen["cb"] is not None  # ...and did not drop the wiring
        assert seen["cb"] is app.state.broadcast_new_alerts  # ...passing the REAL broadcaster
    finally:
        get_settings.cache_clear()


def test_lifespan_uses_configured_intervals(monkeypatch):
    monkeypatch.setenv("ENABLE_SCHEDULER", "true")
    monkeypatch.setenv("ALERT_INGESTION_INTERVAL_SECONDS", "123")
    monkeypatch.setenv("MARINE_INGESTION_INTERVAL_SECONDS", "456")
    monkeypatch.setenv("GFS_INGESTION_INTERVAL_SECONDS", "789")
    get_settings.cache_clear()
    mock_start = MagicMock()
    monkeypatch.setattr("app.main.IngestionScheduler.start", mock_start)
    monkeypatch.setattr("app.main.IngestionScheduler.stop", MagicMock())

    try:
        _run_lifespan_once()

        jobs = mock_start.call_args[0][0]
        intervals = {name: interval for name, _fn, interval in jobs}
        assert intervals["alerts"] == 123
        assert intervals["marine"] == 456
        assert intervals["gfs"] == 789
    finally:
        get_settings.cache_clear()
