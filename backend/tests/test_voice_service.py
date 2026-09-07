from app.providers.speech import SynthesisResult, TranscriptionResult
from app.voice.service import voice_chat


class _FakeSTT:
    def __init__(self, result: TranscriptionResult):
        self._result = result
        self.calls = []

    def transcribe(self, audio_base64, audio_format, language):
        self.calls.append((audio_base64, audio_format, language))
        return self._result


class _FakeTTS:
    def __init__(self, result: SynthesisResult):
        self._result = result
        self.calls = []

    def synthesize(self, text, language):
        self.calls.append((text, language))
        return self._result


def _fake_chat_turn(message, history=None, provider=None):
    return {"reply": f"Reply to: {message}", "history": (history or []) + [{"role": "user", "content": message}]}


def test_voice_chat_transcribes_chats_and_synthesizes():
    stt = _FakeSTT(TranscriptionResult(text="मुंबई में मौसम कैसा है", source_language="hi", raw_payload={}))
    tts = _FakeTTS(SynthesisResult(audio_base64="ZmFrZS1hdWRpbw==", audio_format="wav", raw_payload={}))

    result = voice_chat(
        audio_base64="aW5wdXQtYXVkaW8=",
        audio_format="wav",
        language="hi",
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_fake_chat_turn,
    )

    assert result["transcript"] == "मुंबई में मौसम कैसा है"
    assert result["reply_text"] == "Reply to: मुंबई में मौसम कैसा है"
    assert result["reply_audio_base64"] == "ZmFrZS1hdWRpbw=="
    assert stt.calls == [("aW5wdXQtYXVkaW8=", "wav", "hi")]
    assert tts.calls == [("Reply to: मुंबई में मौसम कैसा है", "hi")]


def test_voice_chat_passes_history_through_to_chat_fn():
    stt = _FakeSTT(TranscriptionResult(text="hello", source_language="en", raw_payload={}))
    tts = _FakeTTS(SynthesisResult(audio_base64="YXVkaW8=", audio_format="wav", raw_payload={}))
    prior_history = [{"role": "user", "content": "earlier"}]

    result = voice_chat(
        audio_base64="YQ==",
        audio_format="wav",
        language="en",
        history=prior_history,
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_fake_chat_turn,
    )

    assert result["history"][0] == {"role": "user", "content": "earlier"}
    assert result["history"][-1] == {"role": "user", "content": "hello"}


def test_voice_chat_returns_transcript_even_if_reply_is_empty():
    stt = _FakeSTT(TranscriptionResult(text="silence test", source_language="en", raw_payload={}))
    tts = _FakeTTS(SynthesisResult(audio_base64="", audio_format="wav", raw_payload={}))

    def _empty_chat_turn(message, history=None, provider=None):
        return {"reply": "", "history": []}

    result = voice_chat(
        audio_base64="eA==",
        audio_format="wav",
        language="en",
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_empty_chat_turn,
    )

    assert result["transcript"] == "silence test"
    assert result["reply_text"] == ""
    assert tts.calls == []
    assert result["reply_audio_base64"] == ""
