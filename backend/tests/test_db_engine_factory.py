from app.db import get_engine


def test_get_engine_reflects_env_override_after_cache_clear(monkeypatch, reset_db_caches):
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql+psycopg://weathergpt:weathergpt_dev@127.0.0.1:59999/weathergpt",
    )
    engine = get_engine()
    assert engine.url.host == "127.0.0.1"
    assert engine.url.port == 59999
    assert engine.url.database == "weathergpt"
