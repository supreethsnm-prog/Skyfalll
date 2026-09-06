"""Selects which LLM vendor backs the chat endpoint.

The choice is configuration, not architecture: every provider here satisfies
the same LLMProvider Protocol, so adding a vendor means adding an adapter and
one branch below.
"""

from app.config import get_settings
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.gemini import GeminiLLMProvider
from app.providers.llm import LLMProvider

_PROVIDERS = {
    "anthropic": AnthropicLLMProvider,
    "gemini": GeminiLLMProvider,
}


def build_llm_provider() -> LLMProvider:
    settings = get_settings()
    choice = (settings.llm_provider or "auto").strip().lower()

    if choice != "auto":
        provider_class = _PROVIDERS.get(choice)
        if provider_class is None:
            raise ValueError(
                f"Unknown LLM_PROVIDER {choice!r}. Use 'auto', "
                f"{', '.join(repr(name) for name in _PROVIDERS)}."
            )
        return provider_class()

    if settings.anthropic_api_key:
        return AnthropicLLMProvider()
    if settings.gemini_api_key:
        return GeminiLLMProvider()

    raise ValueError(
        "No LLM API key configured. Set ANTHROPIC_API_KEY or GEMINI_API_KEY "
        "in backend/.env to enable chat."
    )
