from app.voice.detect import pick_retry_language, script_of
from app.voice.service import voice_chat


def test_script_of_unique_scripts():
    assert script_of("What is the weather") == "latin"
    assert script_of("मुंबई में मौसम") == "devanagari"
    assert script_of("ನಾಳೆ ಹುಬ್ಬಳ್ಳಿಯಲ್ಲಿ") == "kannada"
    assert script_of("హైదరాబాద్") == "telugu"


def test_pick_retry_unique_script_no_judge():
    assert pick_retry_language("What is the weather", "hi") == "en"
    assert pick_retry_language("ನಾಳೆ ಹುಬ್ಬಳ್ಳಿಯಲ್ಲಿ", "hi") == "kn"
    assert pick_retry_language("मुंबई में मौसम", "hi") is None


def test_pick_retry_romanized_hindi_needs_judge():
    # Global en, spoken Hindi romanized in Latin: script alone says "en"
    # (matches fallback) — only the LLM judge can rescue it.
    assert pick_retry_language("hubli mein kal ka mausam kaisa rahega", "en") is None
    assert (
        pick_retry_language("hubli mein kal ka mausam kaisa rahega", "en", lambda t: "hi")
        == "hi"
    )


def test_pick_retry_devanagari_family_uses_judge():
    assert pick_retry_language("मुंबई में मौसम", "hi", lambda t: "mr") == "mr"
    # Tie: fallback in family wins, no retry.
    assert pick_retry_language("मुंबई में मौसम", "hi", lambda t: "hi") is None
    # Fallback outside family: first family member (hi).
    assert pick_retry_language("मुंबई में मौसम", "en", lambda t: None) == "hi"


class _FakeSTT:
    def __init__(self, transcripts):
        self._transcripts = list(transcripts)
        self.calls = []

    def transcribe(self, audio_base64, audio_format, language, sampling_rate=16000):
        from app.providers.speech import TranscriptionResult

        self.calls.append(language)
        text = self._transcripts[min(len(self.calls) - 1, len(self._transcripts) - 1)]
        return TranscriptionResult(text=text, source_language=language, raw_payload={})

    def close(self):
        pass


class _FakeTTS:
    def __init__(self):
        self.calls = []

    def synthesize(self, text, language):
        from app.providers.speech import SynthesisResult

        self.calls.append(language)
        return SynthesisResult(audio_base64="ZmFrZQ==", audio_format="wav", raw_payload={})

    def close(self):
        pass


def _chat_fn(message, history):
    return {"reply": "ok reply", "history": [{"role": "user", "content": message}]}


def test_voice_chat_auto_retries_once_and_reports_detected_language():
    stt = _FakeSTT(["What is the weather", "What is the weather"])
    tts = _FakeTTS()
    result = voice_chat(
        audio_base64="ZmFrZQ==",
        audio_format="wav",
        language="hi",
        history=None,
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_chat_fn,
        auto_detect=True,
    )
    assert stt.calls == ["hi", "en"]
    assert result["detected_language"] == "en"
    # Reply TTS follows the DETECTED language, not try-1.
    assert tts.calls == ["en"]


def test_voice_chat_auto_no_retry_when_already_matching():
    stt = _FakeSTT(["मुंबई में मौसम"])
    tts = _FakeTTS()
    result = voice_chat(
        audio_base64="ZmFrZQ==",
        audio_format="wav",
        language="hi",
        history=None,
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_chat_fn,
        auto_detect=True,
    )
    assert stt.calls == ["hi"]
    assert result["detected_language"] == "hi"


def test_voice_chat_legacy_path_unchanged_without_auto():
    stt = _FakeSTT(["What is the weather"])
    tts = _FakeTTS()
    result = voice_chat(
        audio_base64="ZmFrZQ==",
        audio_format="wav",
        language="hi",
        history=None,
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_chat_fn,
    )
    assert stt.calls == ["hi"]
    assert result["detected_language"] == "hi"
    assert "transcript" in result
