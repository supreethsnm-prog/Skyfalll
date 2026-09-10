from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class TranslationResult:
    text: str
    source_language: str
    target_language: str
    raw_payload: dict[str, Any]


class TranslatorProvider(Protocol):
    def translate(self, text: str, source_language: str, target_language: str) -> TranslationResult: ...
