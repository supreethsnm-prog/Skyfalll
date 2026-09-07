import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app, get_llm_provider
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.llm import LLMTurn
from tests.conftest import FakeLLMProvider

client = TestClient(app)


@pytest.fixture
def override_llm(request):
    def _set(provider):
        app.dependency_overrides[get_llm_provider] = lambda: provider

    yield _set
    app.dependency_overrides.pop(get_llm_provider, None)


def test_chat_endpoint_returns_reply_and_history(override_llm):
    provider = FakeLLMProvider([LLMTurn(text="Hello!", tool_calls=[], stop_reason="end_turn")])
    override_llm(provider)

    response = client.post("/chat", json={"message": "Hi"})

    assert response.status_code == 200
    body = response.json()
    assert body["reply"] == "Hello!"
    assert isinstance(body["history"], list)


def test_chat_endpoint_accepts_prior_history(override_llm):
    provider = FakeLLMProvider([LLMTurn(text="Still here.", tool_calls=[], stop_reason="end_turn")])
    override_llm(provider)

    prior_history = [
        {"role": "user", "content": "Hi"},
        {"role": "assistant", "content": "Hello!"},
    ]
    response = client.post(
        "/chat", json={"message": "You still there?", "history": prior_history}
    )

    assert response.status_code == 200
    assert response.json()["reply"] == "Still here."
    sent_history = provider.calls[0]["history"]
    assert sent_history[0] == {"role": "user", "content": "Hi"}
    assert sent_history[-1] == {"role": "user", "content": "You still there?"}


def test_chat_endpoint_returns_503_when_api_key_missing(monkeypatch):
    # No dependency override here — let the real get_llm_provider run and hit
    # the missing-key path, so a diagnostic 503 replaces what would otherwise
    # be FastAPI's opaque default 500.
    #
    # get_llm_provider now goes through build_llm_provider(), which tries
    # Anthropic then Gemini before raising, so both keys must be isolated.
    # backend/.env has real entries for both on dev machines, and
    # pydantic-settings falls back to reading it directly whenever a var is
    # absent from os.environ — so delenv alone would not isolate this test.
    # An empty-but-present env var takes precedence over that dotenv
    # fallback, so use setenv("") for both.
    monkeypatch.setenv("ANTHROPIC_API_KEY", "")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    get_settings.cache_clear()
    try:
        response = client.post("/chat", json={"message": "Hi"})

        assert response.status_code == 503
        assert "ANTHROPIC_API_KEY" in response.json()["detail"]
    finally:
        get_settings.cache_clear()


def test_chat_endpoint_returns_422_for_malformed_history(override_llm):
    # FakeLLMProvider ignores history content entirely, so this must exercise
    # the real translation logic (AnthropicLLMProvider._translate_history,
    # which raises ValueError on an unknown role) via a provider with an
    # injected mock client — no real network involved.
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"content": [], "stop_reason": "end_turn"})

    mock_client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=mock_client)
    override_llm(provider)

    response = client.post(
        "/chat",
        json={"message": "Hi", "history": [{"role": "not_a_real_role", "content": "x"}]},
    )

    assert response.status_code == 422
    assert "not_a_real_role" in response.json()["detail"]


def test_chat_endpoint_returns_422_for_empty_message(override_llm):
    provider = FakeLLMProvider([LLMTurn(text="Hello!", tool_calls=[], stop_reason="end_turn")])
    override_llm(provider)

    response = client.post("/chat", json={"message": ""})

    assert response.status_code == 422


def test_chat_endpoint_returns_502_for_invalid_json_from_llm_provider(override_llm):
    # A malformed/unparseable body from the LLM vendor must NOT be reported
    # as "invalid history" (422) — that blames the client for a vendor-side
    # failure. json.JSONDecodeError is a ValueError subclass, so this
    # requires its own except clause ordered BEFORE the (KeyError, ValueError)
    # one, or the broader clause would catch it first.
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"not valid json{{{")

    mock_client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=mock_client)
    override_llm(provider)

    response = client.post("/chat", json={"message": "Hi"})

    assert response.status_code == 502
    assert "history" not in response.json()["detail"].lower()


def test_chat_endpoint_returns_503_when_llm_provider_is_unavailable(override_llm, monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503)

    mock_client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=mock_client)
    override_llm(provider)

    response = client.post("/chat", json={"message": "Hi"})

    assert response.status_code == 503


def test_chat_endpoint_returns_503_on_connection_failure(override_llm, monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)

    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused")

    mock_client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=mock_client)
    override_llm(provider)

    response = client.post("/chat", json={"message": "Hi"})

    assert response.status_code == 503
