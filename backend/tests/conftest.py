import pytest
from sqlalchemy import delete

from app.config import get_settings
from app.db import get_engine
from app.models import Alert, GeocodeCache, MetarReading, PfzZone, WeatherReading
from app.providers.llm import LLMTurn
from app.providers.marine import PfzZoneData
from app.providers.warning import AlertData


class FakeLLMProvider:
    def __init__(self, turns: list[LLMTurn]):
        self._turns = list(turns)
        self.calls: list[dict] = []

    def generate(self, system, history, tools):
        self.calls.append({"system": system, "history": [dict(h) for h in history], "tools": tools})
        return self._turns.pop(0)


class FakeWarningProvider:
    def __init__(self, alerts: list[AlertData]):
        self._alerts = alerts

    def fetch_alerts(self) -> list[AlertData]:
        return self._alerts


class _FakeMarineProvider:
    def __init__(self, zones: list[PfzZoneData]):
        self._zones = zones

    def fetch_pfz_zones(self) -> list[PfzZoneData]:
        return self._zones


@pytest.fixture
def reset_db_caches():
    get_settings.cache_clear()
    get_engine.cache_clear()
    yield
    get_settings.cache_clear()
    get_engine.cache_clear()


def _truncate(model) -> None:
    with get_engine().begin() as conn:
        conn.execute(delete(model))


# Each fixture clears its table both BEFORE and after the test. Cleaning only
# on teardown leaves tests at the mercy of whatever is already in the shared
# dev database — running the app locally (or a previously crashed run) would
# otherwise leave rows behind that collide with a test's own seeded fixtures.
@pytest.fixture
def clean_alerts_table():
    _truncate(Alert)
    yield
    _truncate(Alert)


@pytest.fixture
def clean_weather_readings():
    _truncate(WeatherReading)
    yield
    _truncate(WeatherReading)


@pytest.fixture
def clean_geocode_cache():
    _truncate(GeocodeCache)
    yield
    _truncate(GeocodeCache)


@pytest.fixture
def clean_metar_readings():
    _truncate(MetarReading)
    yield
    _truncate(MetarReading)


@pytest.fixture
def clean_pfz_zones():
    _truncate(PfzZone)
    yield
    _truncate(PfzZone)
