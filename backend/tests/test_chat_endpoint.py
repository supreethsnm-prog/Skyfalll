import pytest
from fastapi.testclient import TestClient

from app.main import app, get_llm_provider
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
