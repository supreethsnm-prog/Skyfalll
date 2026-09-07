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
        assert job_names == {"alerts", "marine"}
        mock_stop.assert_called_once()
    finally:
        get_settings.cache_clear()


def test_lifespan_uses_configured_intervals(monkeypatch):
    monkeypatch.setenv("ENABLE_SCHEDULER", "true")
    monkeypatch.setenv("ALERT_INGESTION_INTERVAL_SECONDS", "123")
    monkeypatch.setenv("MARINE_INGESTION_INTERVAL_SECONDS", "456")
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
    finally:
        get_settings.cache_clear()
