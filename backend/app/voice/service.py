"""Voice orchestration: audio in -> transcript -> chat_turn -> reply -> audio out.

chat_turn (app/chat/service.py) is used completely unmodified — voice is a
new INPUT/OUTPUT modality around the exact same tool-calling loop text chat
already uses, not a separate conversational path. This is deliberate:
every guarantee chat_turn already has (grounding via tools, retry-backed
LLM calls, the multi-round tool-iteration cap) applies to voice for free.
"""

from collections.abc import Callable

from app.chat.service import chat_turn
from app.providers.bhashini import BhashiniSpeechProvider
from app.providers.speech import SpeechToTextProvider, TextToSpeechProvider


def voice_chat(
    audio_base64: str,
    audio_format: str,
    language: str,
    history: list[dict] | None = None,
    stt_provider: SpeechToTextProvider | None = None,
    tts_provider: TextToSpeechProvider | None = None,
    chat_fn: Callable[..., dict] = chat_turn,
) -> dict:
    owns_stt = stt_provider is None
    owns_tts = tts_provider is None
    stt = stt_provider or BhashiniSpeechProvider()
    tts = tts_provider or BhashiniSpeechProvider()
    try:
        transcription = stt.transcribe(audio_base64=audio_base64, audio_format=audio_format, language=language)
        chat_result = chat_fn(transcription.text, history)
        reply_text = chat_result["reply"]

        reply_audio_base64 = ""
        if reply_text:
            synthesis = tts.synthesize(text=reply_text, language=language)
            reply_audio_base64 = synthesis.audio_base64

        return {
            "transcript": transcription.text,
            "reply_text": reply_text,
            "reply_audio_base64": reply_audio_base64,
            "history": chat_result["history"],
        }
    finally:
        if owns_stt and hasattr(stt, "close"):
            stt.close()
        # Defensive: if a future refactor shares one instance across both roles when neither is injected, don't double-close.
        if owns_tts and tts is not stt and hasattr(tts, "close"):
            tts.close()
