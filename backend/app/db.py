from functools import lru_cache

from sqlalchemy import create_engine, text

from app.config import get_settings


@lru_cache
def get_engine():
    return create_engine(get_settings().database_url, pool_pre_ping=True)


def check_db_connection() -> None:
    with get_engine().connect() as conn:
        conn.execute(text("SELECT 1"))
