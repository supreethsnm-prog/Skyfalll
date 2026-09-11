from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
_ROOT_ENV_FILE = Path(__file__).resolve().parent.parent.parent / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(_ENV_FILE, _ROOT_ENV_FILE), extra="ignore"
    )

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
    gemini_model: str = "gemini-3.5-flash"
    gemini_max_tokens: int = 1024
    llm_provider: str = "auto"
    enable_scheduler: bool = False
    alert_ingestion_interval_seconds: int = 300
    marine_ingestion_interval_seconds: int = 86400
    # 6 hours — matches GFS's own run cadence; discover_latest_run() is cheap
    # (a handful of HEAD requests) so checking every 6 hours won't over-fetch
    # when nothing new has been published.
    gfs_ingestion_interval_seconds: int = 21600
    internal_api_key: str | None = None
    cors_allowed_origins: str = (
        "http://localhost:3000,http://localhost:5173,"
        "http://127.0.0.1:3000,http://127.0.0.1:5173"
    )
    bhashini_user_id: str | None = None
    # Canonical ULCA API key for the discovery call header `ulcaApiKey`.
    # BHASHINI_UDYAT_KEY is accepted as a legacy alias for the same value
    # (UDYAT is the ULCA dashboard name) so existing .env files keep working.
    bhashini_api_key: str | None = None
    bhashini_udyat_key: str | None = None
    # Dhruva compute token returned by discovery as
    # pipelineInferenceAPIEndPoint.inferenceApiKey.value. Distinct from the
    # ULCA API key above — never send this as `ulcaApiKey` (that yields
    # `400 ulcaApiKey does not exist`).
    bhashini_inference_key: str | None = None
    # MeitY public multitask pipeline (ASR+NMT+TTS, 22 scheduled languages +
    # English), live-verified 2026-09-10. Shared catalogue entry, not a
    # per-user secret. Override in .env for a custom pipeline.
    bhashini_pipeline_id: str | None = "64392f96daac500b55c543cd"
    cds_api_key: str | None = None


def _read_env_value(key: str) -> str | None:
    import os

    # An empty env var is the test suite's way of isolating from .env — respect it.
    if os.environ.get(key) == "":
        return None

    # If the ambient environment has a non-AQ key, keep it; if it's an AQ token, prefer .env
    ambient = os.environ.get(key)
    if ambient and not ambient.startswith("AQ."):
        return ambient

    for path in (_ENV_FILE, _ROOT_ENV_FILE):
        if path.exists():
            for line in path.read_text().splitlines():
                line = line.strip()
                if line.startswith(f"{key}=") and not line.startswith("#"):
                    val = line.split("=", 1)[1].strip().strip("'\"")
                    if val:
                        return val
    return ambient


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    file_gemini_key = _read_env_value("GEMINI_API_KEY")
    if file_gemini_key:
        settings.gemini_api_key = file_gemini_key
    file_anthropic_key = _read_env_value("ANTHROPIC_API_KEY")
    if file_anthropic_key:
        settings.anthropic_api_key = file_anthropic_key
    return settings
