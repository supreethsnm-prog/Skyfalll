import io
import json
import wave

import httpx
from fastapi.testclient import TestClient

from app.main import app, get_stt_provider, get_tts_provider
from app.providers.speech import SynthesisResult, TranscriptionResult

client = TestClient(app)


def _wav_bytes(sample_rate: int = 16000, frames: int = 10) -> bytes:
    """A real, minimal, silent mono 16-bit WAV.

    The endpoint now parses the upload with the stdlib `wave` module to learn
    its true sampling rate, so tests can no longer hand it a `b"RIFF...fake"`
    placeholder — those bytes are (correctly) rejected as not-a-WAV.
    """
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(b"\x00\x00" * frames)
    return buf.getvalue()


class _FakeSTT:
    def __init__(self, error: Exception | None = None):
        self._error = error
        self.calls: list[dict] = []

    def transcribe(self, audio_base64, audio_format, language, sampling_rate=16000):
        self.calls.append(
            {
                "audio_base64": audio_base64,
                "audio_format": audio_format,
                "language": language,
                "sampling_rate": sampling_rate,
            }
        )
        if self._error is not None:
            raise self._error
        return TranscriptionResult(text="test transcript", source_language=language, raw_payload={})

    def close(self):
        pass


class _FakeTTS:
    def __init__(self, error: Exception | None = None):
        self._error = error

    def synthesize(self, text, language):
        if self._error is not None:
            raise self._error
        return SynthesisResult(audio_base64="ZmFrZS1hdWRpbw==", audio_format="wav", raw_payload={})

    def close(self):
        pass


def _http_status_error() -> httpx.HTTPStatusError:
    request = httpx.Request("POST", "http://x")
    return httpx.HTTPStatusError("boom", request=request, response=httpx.Response(503, request=request))


def _override(fake_stt=None, fake_tts=None):
    if fake_stt is not None:
        app.dependency_overrides[get_stt_provider] = lambda: fake_stt
    if fake_tts is not None:
        app.dependency_overrides[get_tts_provider] = lambda: fake_tts


def _clear_overrides():
    app.dependency_overrides.pop(get_stt_provider, None)
    app.dependency_overrides.pop(get_tts_provider, None)


def _override_llm(*turn_texts):
    from app.main import get_llm_provider
    from app.providers.llm import LLMTurn
    from tests.conftest import FakeLLMProvider

    fake_llm = FakeLLMProvider(
        [LLMTurn(text=text, tool_calls=[], stop_reason="end_turn") for text in turn_texts]
    )
    app.dependency_overrides[get_llm_provider] = lambda: fake_llm
    return fake_llm


def _clear_llm_override():
    from app.main import get_llm_provider

    app.dependency_overrides.pop(get_llm_provider, None)


def test_voice_languages_returns_a_static_list():
    response = client.get("/voice/languages")
    assert response.status_code == 200
    body = response.json()
    assert "languages" in body
    assert any(lang["code"] == "hi" for lang in body["languages"])
    assert any(lang["code"] == "en" for lang in body["languages"])


def test_voice_chat_returns_transcript_and_reply_audio():
    _override_llm("Here is your reply.")
    _override(fake_stt=_FakeSTT(), fake_tts=_FakeTTS())
    try:
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(_wav_bytes()), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["transcript"] == "test transcript"
        assert body["reply_text"] == "Here is your reply."
        assert body["reply_audio_base64"] == "ZmFrZS1hdWRpbw=="
    finally:
        _clear_overrides()
        _clear_llm_override()


def test_voice_chat_rejects_non_wav_upload():
    response = client.post(
        "/voice/chat",
        files={"audio": ("test.mp3", io.BytesIO(b"fake mp3 bytes"), "audio/mpeg")},
        data={"language": "hi"},
    )
    assert response.status_code == 422


def test_voice_chat_returns_503_when_bhashini_not_configured(monkeypatch):
    monkeypatch.setenv("BHASHINI_USER_ID", "")
    monkeypatch.setenv("BHASHINI_API_KEY", "")
    monkeypatch.setenv("BHASHINI_UDYAT_KEY", "")
    monkeypatch.setenv("BHASHINI_INFERENCE_KEY", "")
    monkeypatch.setenv("BHASHINI_PIPELINE_ID", "")
    from app.config import get_settings

    get_settings.cache_clear()
    try:
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(_wav_bytes()), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 503
    finally:
        get_settings.cache_clear()


# --- Fix 1 (C1): the endpoint translates provider failures into clean statuses ---


def test_voice_chat_returns_503_when_provider_call_fails():
    # A retryable BHASHINI failure that survived app/providers/retry.py and was
    # re-raised. Without exception handling on the endpoint this surfaces as an
    # opaque 500 (or, under TestClient, an uncaught exception).
    _override_llm("unused")
    _override(fake_stt=_FakeSTT(error=_http_status_error()), fake_tts=_FakeTTS())
    try:
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(_wav_bytes()), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 503
        assert "temporarily unavailable" in response.json()["detail"]
    finally:
        _clear_overrides()
        _clear_llm_override()


def test_voice_chat_returns_502_when_provider_payload_is_malformed():
    # Stands in for BhashiniSpeechProvider.transcribe's
    # payload["pipelineResponse"][0]["output"][0]["source"] walk blowing up on a
    # truncated vendor response. The vendor's fault, not the client's: 502, and
    # specifically NOT the 422 that a bad `history` field gets.
    _override_llm("unused")
    _override(fake_stt=_FakeSTT(error=KeyError("output")), fake_tts=_FakeTTS())
    try:
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(_wav_bytes()), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 502
        assert "invalid response" in response.json()["detail"]
    finally:
        _clear_overrides()
        _clear_llm_override()


# --- Fix 2 (I2): the real WAV sampling rate reaches the STT provider ---


def test_voice_chat_passes_real_wav_sampling_rate_to_stt():
    _override_llm("Here is your reply.")
    fake_stt = _FakeSTT()
    _override(fake_stt=fake_stt, fake_tts=_FakeTTS())
    try:
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(_wav_bytes(sample_rate=8000)), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 200
        # 8000, not the 16000 the provider used to hardcode.
        assert fake_stt.calls[0]["sampling_rate"] == 8000
    finally:
        _clear_overrides()
        _clear_llm_override()


def test_voice_chat_rejects_wav_named_file_that_is_not_valid_wav():
    response = client.post(
        "/voice/chat",
        files={"audio": ("test.wav", io.BytesIO(b"not a real wav file"), "audio/wav")},
        data={"language": "hi"},
    )
    assert response.status_code == 422
    assert "not a valid WAV" in response.json()["detail"]


# --- Fix 3 (I3): history is threaded through /voice/chat ---


def test_voice_chat_threads_history_through_to_the_llm():
    fake_llm = _override_llm("Here is your reply.")
    _override(fake_stt=_FakeSTT(), fake_tts=_FakeTTS())
    try:
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(_wav_bytes()), "audio/wav")},
            data={
                "language": "hi",
                "history": json.dumps([{"role": "user", "content": "earlier"}]),
            },
        )
        assert response.status_code == 200
        # Discriminating: if history were ignored, the LLM would have been
        # called with only the transcript turn, and the returned history would
        # start at "test transcript" rather than "earlier".
        assert fake_llm.calls[0]["history"][0] == {"role": "user", "content": "earlier"}
        assert fake_llm.calls[0]["history"][-1] == {"role": "user", "content": "test transcript"}
        assert response.json()["history"][0] == {"role": "user", "content": "earlier"}
    finally:
        _clear_overrides()
        _clear_llm_override()


def test_voice_chat_rejects_malformed_history_json():
    _override_llm("unused")
    _override(fake_stt=_FakeSTT(), fake_tts=_FakeTTS())
    try:
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(_wav_bytes()), "audio/wav")},
            data={"language": "hi", "history": "not json"},
        )
        # The client's fault — 422, distinct from the 502 a malformed VENDOR
        # payload gets.
        assert response.status_code == 422
        assert "Invalid history" in response.json()["detail"]
    finally:
        _clear_overrides()
        _clear_llm_override()


# --- Fix 4 (I4): upload size limit ---


def test_voice_chat_rejects_oversized_upload():
    # Deliberately not valid WAV data: the size check must fire before any
    # attempt to parse the bytes, so this must be a 413 and not the 422 that
    # invalid-WAV bytes would otherwise earn.
    oversized = b"RIFF" + b"\x00" * (11 * 1024 * 1024)
    response = client.post(
        "/voice/chat",
        files={"audio": ("big.wav", io.BytesIO(oversized), "audio/wav")},
        data={"language": "hi"},
    )
    assert response.status_code == 413
    assert "too large" in response.json()["detail"]


def test_voice_chat_forwards_user_location():
    fake_llm = _override_llm("It will rain.")
    _override(fake_stt=_FakeSTT(), fake_tts=_FakeTTS())
    try:
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(_wav_bytes()), "audio/wav")},
            data={
                "language": "hi",
                "latitude": "12.97",
                "longitude": "77.59",
                "place_name": "Bengaluru",
            },
        )
        assert response.status_code == 200
        assert "Bengaluru" in fake_llm.calls[0]["system"]
        assert "12.97" in fake_llm.calls[0]["system"]
    finally:
        _clear_overrides()
        _clear_llm_override()

