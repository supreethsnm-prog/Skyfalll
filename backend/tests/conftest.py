import pytest
from sqlalchemy import delete

from app.config import get_settings
from app.db import get_engine
from app.models import Alert
from app.providers.warning import AlertData


class FakeWarningProvider:
    def __init__(self, alerts: list[AlertData]):
        self._alerts = alerts

    def fetch_alerts(self) -> list[AlertData]:
        return self._alerts


@pytest.fixture
def reset_db_caches():
    get_settings.cache_clear()
    get_engine.cache_clear()
    yield
    get_settings.cache_clear()
    get_engine.cache_clear()


@pytest.fixture
def clean_alerts_table():
    yield
    with get_engine().begin() as conn:
        conn.execute(delete(Alert))
