from sqlalchemy import create_engine, text

from app.config import get_settings

engine = create_engine(get_settings().database_url, pool_pre_ping=True)


def check_db_connection() -> bool:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return True
