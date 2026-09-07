import base64
import io

from fastapi.testclient import TestClient

from app.main import app, get_stt_provider, get_tts_provider
from app.providers.speech import SynthesisResult, TranscriptionResult

client = TestClient(app)


class _FakeSTT:
    def transcribe(self, audio_base64, audio_format, language):
        return TranscriptionResult(text="test transcript", source_language=language, raw_payload={})

    def close(self):
        pass


class _FakeTTS:
    def synthesize(self, text, language):
        return SynthesisResult(audio_base64="ZmFrZS1hdWRpbw==", audio_format="wav", raw_payload={})

    def close(self):
        pass


def _override(fake_stt=None, fake_tts=None):
    if fake_stt is not None:
        app.dependency_overrides[get_stt_provider] = lambda: fake_stt
    if fake_tts is not None:
        app.dependency_overrides[get_tts_provider] = lambda: fake_tts


def _clear_overrides():
    app.dependency_overrides.pop(get_stt_provider, None)
    app.dependency_overrides.pop(get_tts_provider, None)


def test_voice_languages_returns_a_static_list():
    response = client.get("/voice/languages")
    assert response.status_code == 200
    body = response.json()
    assert "languages" in body
    assert any(lang["code"] == "hi" for lang in body["languages"])
    assert any(lang["code"] == "en" for lang in body["languages"])


def test_voice_chat_returns_transcript_and_reply_audio(monkeypatch):
    from app.providers.llm import LLMTurn
    from tests.conftest import FakeLLMProvider
    from app.main import get_llm_provider

    fake_llm = FakeLLMProvider([LLMTurn(text="Here is your reply.", tool_calls=[], stop_reason="end_turn")])
    app.dependency_overrides[get_llm_provider] = lambda: fake_llm
    _override(fake_stt=_FakeSTT(), fake_tts=_FakeTTS())
    try:
        wav_bytes = b"RIFF....WAVEfmt fake wav bytes"
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(wav_bytes), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["transcript"] == "test transcript"
        assert body["reply_text"] == "Here is your reply."
        assert body["reply_audio_base64"] == "ZmFrZS1hdWRpbw=="
    finally:
        _clear_overrides()
        app.dependency_overrides.pop(get_llm_provider, None)


def test_voice_chat_rejects_non_wav_upload():
    response = client.post(
        "/voice/chat",
        files={"audio": ("test.mp3", io.BytesIO(b"fake mp3 bytes"), "audio/mpeg")},
        data={"language": "hi"},
    )
    assert response.status_code == 422


def test_voice_chat_returns_503_when_bhashini_not_configured(monkeypatch):
    monkeypatch.setenv("BHASHINI_USER_ID", "")
    monkeypatch.setenv("BHASHINI_INFERENCE_KEY", "")
    monkeypatch.setenv("BHASHINI_PIPELINE_ID", "")
    from app.config import get_settings

    get_settings.cache_clear()
    try:
        wav_bytes = b"RIFF....WAVEfmt fake wav bytes"
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(wav_bytes), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 503
    finally:
        get_settings.cache_clear()
