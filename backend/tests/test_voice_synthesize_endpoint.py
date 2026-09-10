from fastapi.testclient import TestClient

from app.main import app
from app.providers.speech import SynthesisResult


class _FakeTts:
    def __init__(self, audio_base64="d2F2ZWZvcm0=", audio_format="wav"):
        self._audio_base64 = audio_base64
        self._audio_format = audio_format
        self.calls = []

    def synthesize(self, text, language):
        self.calls.append((text, language))
        return SynthesisResult(
            audio_base64=self._audio_base64,
            audio_format=self._audio_format,
            raw_payload={},
        )

    def close(self):
        pass


class _RaisingTts:
    def __init__(self, exc):
        self._exc = exc

    def synthesize(self, text, language):
        raise self._exc

    def close(self):
        pass


def test_synthesize_endpoint_returns_audio():
    from app import main

    fake = _FakeTts()
    app.dependency_overrides[main.get_tts_provider] = lambda: fake
    try:
        client = TestClient(app)
        resp = client.get(
            "/voice/synthesize", params={"text": "Heavy rainfall expected", "language": "hi"}
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["audio_base64"] == "d2F2ZWZvcm0="
        assert body["audio_format"] == "wav"
        assert fake.calls == [("Heavy rainfall expected", "hi")]
    finally:
        app.dependency_overrides.clear()


def test_synthesize_endpoint_rejects_empty_text():
    from app import main

    fake = _FakeTts()
    app.dependency_overrides[main.get_tts_provider] = lambda: fake
    try:
        client = TestClient(app)
        resp = client.get("/voice/synthesize", params={"text": "", "language": "hi"})
        assert resp.status_code in (404, 422)
    finally:
        app.dependency_overrides.clear()


def test_synthesize_endpoint_maps_malformed_vendor_payload_to_502():
    from app import main

    fake = _RaisingTts(KeyError("pipelineResponse"))
    app.dependency_overrides[main.get_tts_provider] = lambda: fake
    try:
        client = TestClient(app)
        resp = client.get(
            "/voice/synthesize", params={"text": "Heavy rainfall expected", "language": "hi"}
        )
        assert resp.status_code == 502
    finally:
        app.dependency_overrides.clear()


def test_synthesize_endpoint_maps_transport_failure_to_503():
    import httpx

    from app import main

    fake = _RaisingTts(httpx.TransportError("connection reset"))
    app.dependency_overrides[main.get_tts_provider] = lambda: fake
    try:
        client = TestClient(app)
        resp = client.get(
            "/voice/synthesize", params={"text": "Heavy rainfall expected", "language": "hi"}
        )
        assert resp.status_code == 503
    finally:
        app.dependency_overrides.clear()


def test_synthesize_service_validates_inputs():
    import pytest

    from app.voice.service import synthesize_speech

    with pytest.raises(ValueError):
        synthesize_speech(text="  ", language="hi")
    with pytest.raises(ValueError):
        synthesize_speech(text="hello", language="")
