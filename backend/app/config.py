from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=_ENV_FILE, extra="ignore")

    # 127.0.0.1, not "localhost" — "localhost" adds a multi-second
    # IPv6-then-IPv4 resolution stall on this machine before falling back;
    # 127.0.0.1 connects immediately.
    database_url: str = (
        "postgresql+psycopg://weathergpt:weathergpt_dev@127.0.0.1:5432/weathergpt"
    )
    anthropic_api_key: str | None = None
    anthropic_model: str = "claude-sonnet-5"
    anthropic_max_tokens: int = 1024
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-2.5-flash"
    gemini_max_tokens: int = 1024
    llm_provider: str = "auto"
    enable_scheduler: bool = False
    alert_ingestion_interval_seconds: int = 300
    marine_ingestion_interval_seconds: int = 86400


@lru_cache
def get_settings() -> Settings:
    return Settings()
