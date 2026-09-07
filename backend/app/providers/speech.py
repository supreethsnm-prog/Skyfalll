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
    # sampling_rate is optional with a 16000 default so existing callers (and
    # test fakes) that predate it keep working unchanged; callers that know the
    # real rate of the audio they hold should always pass it.
    def transcribe(
        self, audio_base64: str, audio_format: str, language: str, sampling_rate: int = 16000
    ) -> TranscriptionResult: ...


class TextToSpeechProvider(Protocol):
    def synthesize(self, text: str, language: str) -> SynthesisResult: ...
