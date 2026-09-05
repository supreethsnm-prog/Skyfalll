from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=_ENV_FILE, extra="ignore")

    database_url: str = (
        "postgresql+psycopg://weathergpt:weathergpt_dev@localhost:5432/weathergpt"
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
