from fastapi.testclient import TestClient

from app.main import app
from app.providers.translation import TranslationResult


class _FakeTranslator:
    def __init__(self, text="भारी वर्षा की संभावना"):
        self._text = text
        self.calls = []

    def translate(self, text, source_language, target_language):
        self.calls.append((text, source_language, target_language))
        return TranslationResult(
            text=self._text,
            source_language=source_language,
            target_language=target_language,
            raw_payload={},
        )

    def close(self):
        pass


def test_translate_endpoint_returns_translated_text():
    from app import main

    fake = _FakeTranslator()
    app.dependency_overrides[main.get_translator_provider] = lambda: fake
    try:
        client = TestClient(app)
        resp = client.get("/translate", params={"text": "Heavy rainfall expected", "source": "en", "target": "hi"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["translated_text"] == "भारी वर्षा की संभावना"
        assert body["source_language"] == "en"
        assert body["target_language"] == "hi"
        assert fake.calls == [("Heavy rainfall expected", "en", "hi")]
    finally:
        app.dependency_overrides.clear()


def test_translate_endpoint_rejects_empty_text():
    from app import main

    fake = _FakeTranslator()
    app.dependency_overrides[main.get_translator_provider] = lambda: fake
    try:
        client = TestClient(app)
        resp = client.get("/translate", params={"text": "", "source": "en", "target": "hi"})
        assert resp.status_code in (404, 422)
    finally:
        app.dependency_overrides.clear()


def test_translate_service_validates_inputs():
    import pytest

    from app.translation.service import translate_text

    with pytest.raises(ValueError):
        translate_text(text="  ", source_language="en", target_language="hi")
    with pytest.raises(ValueError):
        translate_text(text="hi", source_language="", target_language="hi")
