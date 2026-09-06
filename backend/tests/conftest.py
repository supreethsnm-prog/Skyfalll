import pytest

from app.config import get_settings
from app.db import get_engine


@pytest.fixture
def reset_db_caches():
    get_settings.cache_clear()
    get_engine.cache_clear()
    yield
    get_settings.cache_clear()
    get_engine.cache_clear()
