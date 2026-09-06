import pytest

from app.config import get_settings
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.factory import build_llm_provider
from app.providers.gemini import GeminiLLMProvider


@pytest.fixture
def clean_settings(monkeypatch):
    """Isolate provider selection from ambient env and the settings cache.

    ANTHROPIC_API_KEY and GEMINI_API_KEY both have entries in backend/.env on
    dev machines. pydantic-settings falls back to reading the dotenv file
    directly whenever a var is absent from os.environ, so monkeypatch.delenv
    alone would NOT isolate this fixture from a real key sitting in .env — an
    empty-but-present env var takes precedence over that fallback, so setenv
    with an empty string is used for those two. LLM_PROVIDER has no .env
    entry, so delenv is sufficient there.
    """
    monkeypatch.setenv("ANTHROPIC_API_KEY", "")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    get_settings.cache_clear()
    yield monkeypatch
    get_settings.cache_clear()


def _built(monkeypatch, **env):
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    get_settings.cache_clear()
    provider = build_llm_provider()
    provider.close()
    return provider


def test_auto_selects_gemini_when_only_gemini_key_set(clean_settings):
    provider = _built(clean_settings, GEMINI_API_KEY="g-key")
    assert isinstance(provider, GeminiLLMProvider)


def test_auto_selects_anthropic_when_only_anthropic_key_set(clean_settings):
    provider = _built(clean_settings, ANTHROPIC_API_KEY="a-key")
    assert isinstance(provider, AnthropicLLMProvider)


def test_explicit_choice_wins_over_auto_detection(clean_settings):
    provider = _built(clean_settings, ANTHROPIC_API_KEY="a-key", GEMINI_API_KEY="g-key", LLM_PROVIDER="gemini")
    assert isinstance(provider, GeminiLLMProvider)


def test_explicit_choice_is_case_insensitive(clean_settings):
    provider = _built(clean_settings, GEMINI_API_KEY="g-key", LLM_PROVIDER="Gemini")
    assert isinstance(provider, GeminiLLMProvider)


def test_no_keys_configured_raises_naming_both_env_vars(clean_settings):
    get_settings.cache_clear()
    with pytest.raises(ValueError) as excinfo:
        build_llm_provider()
    message = str(excinfo.value)
    assert "ANTHROPIC_API_KEY" in message
    assert "GEMINI_API_KEY" in message


def test_unknown_provider_name_raises(clean_settings):
    clean_settings.setenv("LLM_PROVIDER", "llama")
    get_settings.cache_clear()
    with pytest.raises(ValueError, match="llama"):
        build_llm_provider()
