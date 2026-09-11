from app.voice.detect import detect_reply_language, pick_retry_language, script_of
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


def test_detect_reply_language_scripts():
    assert detect_reply_language("The temperature is 32C", fallback="hi") == "en"
    assert detect_reply_language("आज दिल्ली में मौसम साफ रहेगा।", fallback="en") == "hi"
    assert detect_reply_language("आज मुंबईत हवामान कसे आहे?", fallback="en") == "mr"
    assert detect_reply_language("ఈ రోజు వాతావరణం బాగుంది", fallback="en") == "te"
    assert detect_reply_language("இன்று வானிலை நன்றாக உள்ளது", fallback="en") == "ta"
    assert detect_reply_language("ನಾಳೆ ಮಳೆಯಾಗುವ ಸಾಧ್ಯತೆಯಿದೆ", fallback="en") == "kn"
    assert detect_reply_language("আজ কলকাতায় আবহাওয়া কেমন থাকবে?", fallback="en") == "bn"
    assert detect_reply_language("આજે અમદાવાદમાં ખૂબ ગરમી છે", fallback="en") == "gu"
    assert detect_reply_language("ਅੱਜ ਅੰਮ੍ਰਿਤਸਰ ਵਿੱਚ ਮੌਸਮ", fallback="en") == "pa"
    assert detect_reply_language("ଆଜି ପାଗ ଭଲ ଅଛି", fallback="en") == "or"
    assert detect_reply_language("आज मौसम", fallback="mr") == "mr"
    assert detect_reply_language("", fallback="en") == "en"


def test_voice_chat_synthesizes_with_reply_language_when_input_was_en():
    # User input was sent with fallback="en", but LLM replies in Hindi.
    stt = _FakeSTT(["kaisa mausam hai"])
    tts = _FakeTTS()

    def _hindi_chat(message, history):
        return {"reply": "आज दिल्ली में मौसम साफ रहेगा।", "history": []}

    result = voice_chat(
        audio_base64="ZmFrZQ==",
        audio_format="wav",
        language="en",
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_hindi_chat,
    )
    assert result["detected_language"] == "en"
    assert result["reply_language"] == "hi"
    # TTS must be called with "hi", NOT "en"
    assert tts.calls == ["hi"]


def test_voice_chat_synthesizes_with_telugu_reply():
    # User input was sent with fallback="en", but LLM replies in Telugu.
    stt = _FakeSTT(["tell me weather"])
    tts = _FakeTTS()

    def _telugu_chat(message, history):
        return {"reply": "ఈ రోజు వాతావరణం బాగుంది", "history": []}

    result = voice_chat(
        audio_base64="ZmFrZQ==",
        audio_format="wav",
        language="en",
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_telugu_chat,
    )
    assert result["reply_language"] == "te"
    assert tts.calls == ["te"]

