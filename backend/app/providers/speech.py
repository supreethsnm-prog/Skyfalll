from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class TranscriptionResult:
    text: str
    source_language: str
    raw_payload: dict[str, Any]


@dataclass
class SynthesisResult:
    audio_base64: str
    audio_format: str
    raw_payload: dict[str, Any]


class SpeechToTextProvider(Protocol):
    def transcribe(self, audio_base64: str, audio_format: str, language: str) -> TranscriptionResult: ...


class TextToSpeechProvider(Protocol):
    def synthesize(self, text: str, language: str) -> SynthesisResult: ...
