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
from app.voice.detect import detect_reply_language, judge_with_llm, pick_retry_language


def synthesize_speech(
    text: str,
    language: str,
    provider: TextToSpeechProvider | None = None,
) -> dict:
    """Text-to-speech for arbitrary already-existing text — the "read
    aloud" action on a chat message, distinct from [voice_chat] below.

    [voice_chat] always synthesizes as the LAST step of a fresh STT ->
    chat_turn -> TTS round trip; there was previously no way to synthesize
    text that already exists (an assistant reply already on screen)
    without re-running the whole pipeline. This is a thin, standalone
    wrapper for exactly that — never cached, per BhashiniSpeechProvider's
    own module docstring (a synthesis result is specific to one utterance).
    """
    if not text or not text.strip():
        raise ValueError("text must be a non-empty string")
    if not language or not language.strip():
        raise ValueError("language is required")
    owns = provider is None
    tts = provider or BhashiniSpeechProvider()
    try:
        result = tts.synthesize(text=text, language=language)
        return {"audio_base64": result.audio_base64, "audio_format": result.audio_format}
    finally:
        if owns and hasattr(tts, "close"):
            tts.close()


def voice_chat(
    audio_base64: str,
    audio_format: str,
    language: str,
    history: list[dict] | None = None,
    sampling_rate: int = 16000,
    stt_provider: SpeechToTextProvider | None = None,
    tts_provider: TextToSpeechProvider | None = None,
    chat_fn: Callable[..., dict] = chat_turn,
    user_location: dict | None = None,
    auto_detect: bool = False,
    lang_judge: Callable[[str], str | None] | None = None,
    llm_for_judge=None,
) -> dict:
    owns_stt = stt_provider is None
    owns_tts = tts_provider is None
    stt = stt_provider or BhashiniSpeechProvider()
    tts = tts_provider or BhashiniSpeechProvider()
    try:
        transcription = stt.transcribe(
            audio_base64=audio_base64,
            audio_format=audio_format,
            language=language,
            sampling_rate=sampling_rate,
        )
        effective_language = language
        # Auto-detect: at most ONE retry (max 2 ASR calls per message).
        # Try-1 runs in `language` (the client's global); script + LLM judge
        # decide whether try-2 in a better language is warranted.
        if auto_detect:
            judge = lang_judge
            if judge is None and llm_for_judge is not None:
                judge = lambda text: judge_with_llm(text, llm_for_judge.generate)
            retry_lang = pick_retry_language(transcription.text, language, judge)
            if retry_lang is not None:
                re_transcription = stt.transcribe(
                    audio_base64=audio_base64,
                    audio_format=audio_format,
                    language=retry_lang,
                    sampling_rate=sampling_rate,
                )
                transcription = re_transcription
                effective_language = retry_lang
        try:
            chat_result = chat_fn(
                transcription.text, history, user_location=user_location
            )
        except TypeError:
            # Back-compat with injected fakes taking (message, history) only.
            chat_result = chat_fn(transcription.text, history)
        reply_text = chat_result["reply"]

        reply_audio_base64 = ""
        reply_language = (
            detect_reply_language(reply_text, fallback=effective_language)
            if reply_text
            else effective_language
        )
        if reply_text:
            synthesis = tts.synthesize(text=reply_text, language=reply_language)
            reply_audio_base64 = synthesis.audio_base64

        return {
            "transcript": transcription.text,
            "detected_language": effective_language,
            "reply_language": reply_language,
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
