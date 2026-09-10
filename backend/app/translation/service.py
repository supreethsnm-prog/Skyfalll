"""Deterministic translation service (Bhashini NMT), never cached.

Thin wrapper over BhashiniSpeechProvider.translate() so chat tools and the
/translate endpoint share one call path. LLM translation stays the default
for free-form chat (fluency, code-mix); use this for exact strings where
numbers/units/terminology must not drift (alerts, advisories, UI labels).
"""

from app.providers.bhashini import BhashiniSpeechProvider
from app.providers.translation import TranslatorProvider


def translate_text(
    text: str,
    source_language: str,
    target_language: str,
    provider: TranslatorProvider | None = None,
) -> dict:
    if not text or not text.strip():
        raise ValueError("text must be a non-empty string")
    if not source_language or not target_language:
        raise ValueError("source_language and target_language are both required")
    owns = provider is None
    translator = provider or BhashiniSpeechProvider()
    try:
        result = translator.translate(
            text=text, source_language=source_language, target_language=target_language
        )
        return {
            "translated_text": result.text,
            "source_language": result.source_language,
            "target_language": result.target_language,
        }
    finally:
        if owns and hasattr(translator, "close"):
            translator.close()
