import httpx
import pytest

from app.config import get_settings
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.llm import ToolSpec


def _client_returning(payload: dict, capture: dict | None = None) -> httpx.Client:
    def handler(request: httpx.Request) -> httpx.Response:
        if capture is not None:
            capture["request_json"] = httpx.Request(
                request.method, request.url, content=request.content
            ).content
            import json as _json

            capture["body"] = _json.loads(request.content)
            capture["headers"] = dict(request.headers)
        return httpx.Response(200, json=payload)

    return httpx.Client(transport=httpx.MockTransport(handler))


def test_generate_raises_without_api_key(monkeypatch):
    # Explicitly control the environment rather than relying on ambient state:
    # if a real ANTHROPIC_API_KEY is ever set in the environment (exactly the
    # state this feature requires once someone configures it), this test must
    # still exercise the no-key path rather than silently no-op'ing.
    #
    # backend/.env has an ANTHROPIC_API_KEY entry on dev machines, and
    # pydantic-settings falls back to reading it directly whenever the var is
    # absent from os.environ — so monkeypatch.delenv alone would NOT isolate
    # this test from a real key sitting in .env. An empty-but-present env var
    # takes precedence over that dotenv fallback, so use setenv("") instead.
    monkeypatch.setenv("ANTHROPIC_API_KEY", "")
    get_settings.cache_clear()
    try:
        with pytest.raises(ValueError, match="ANTHROPIC_API_KEY"):
            AnthropicLLMProvider(api_key=None)
    finally:
        get_settings.cache_clear()


def test_generate_returns_text_only_turn():
    payload = {
        "content": [{"type": "text", "text": "Hello there."}],
        "stop_reason": "end_turn",
    }
    capture: dict = {}
    client = _client_returning(payload, capture)
    provider = AnthropicLLMProvider(api_key="test-key", model="claude-sonnet-5", client=client)

    turn = provider.generate(
        system="You are a test assistant.",
        history=[{"role": "user", "content": "Hi"}],
        tools=[],
    )

    assert turn.text == "Hello there."
    assert turn.tool_calls == []
    assert turn.stop_reason == "end_turn"
    assert capture["headers"]["x-api-key"] == "test-key"
    assert capture["headers"]["anthropic-version"] == "2023-06-01"
    assert capture["body"]["model"] == "claude-sonnet-5"
    assert capture["body"]["system"] == "You are a test assistant."
    assert capture["body"]["messages"] == [{"role": "user", "content": "Hi"}]


def test_generate_returns_tool_use_turn():
    payload = {
        "content": [
            {"type": "text", "text": "Let me check."},
            {
                "type": "tool_use",
                "id": "toolu_abc123",
                "name": "get_weather",
                "input": {"latitude": 19.08, "longitude": 72.88},
            },
        ],
        "stop_reason": "tool_use",
    }
    client = _client_returning(payload)
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    tools = [
        ToolSpec(
            name="get_weather",
            description="Get current weather for a coordinate.",
            input_schema={
                "type": "object",
                "properties": {
                    "latitude": {"type": "number"},
                    "longitude": {"type": "number"},
                },
                "required": ["latitude", "longitude"],
            },
        )
    ]

    turn = provider.generate(
        system="sys", history=[{"role": "user", "content": "Weather in Mumbai?"}], tools=tools
    )

    assert turn.text == "Let me check."
    assert len(turn.tool_calls) == 1
    call = turn.tool_calls[0]
    assert call.id == "toolu_abc123"
    assert call.name == "get_weather"
    assert call.input == {"latitude": 19.08, "longitude": 72.88}
    assert turn.stop_reason == "tool_use"


def test_generate_translates_tool_specs_to_wire_format():
    payload = {"content": [{"type": "text", "text": "ok"}], "stop_reason": "end_turn"}
    capture: dict = {}
    client = _client_returning(payload, capture)
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    tools = [
        ToolSpec(
            name="get_weather",
            description="Get current weather.",
            input_schema={"type": "object", "properties": {}},
        )
    ]
    provider.generate(system="sys", history=[{"role": "user", "content": "hi"}], tools=tools)

    assert capture["body"]["tools"] == [
        {
            "name": "get_weather",
            "description": "Get current weather.",
            "input_schema": {"type": "object", "properties": {}},
        }
    ]


def test_generate_translates_assistant_tool_call_and_tool_result_history():
    payload = {"content": [{"type": "text", "text": "final answer"}], "stop_reason": "end_turn"}
    capture: dict = {}
    client = _client_returning(payload, capture)
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    history = [
        {"role": "user", "content": "Weather in Mumbai?"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {"id": "toolu_1", "name": "get_weather", "input": {"latitude": 19.08, "longitude": 72.88}}
            ],
        },
        {"role": "tool", "tool_call_id": "toolu_1", "content": '{"temperature_c": 28.0}'},
    ]

    provider.generate(system="sys", history=history, tools=[])

    wire_messages = capture["body"]["messages"]
    assert wire_messages[0] == {"role": "user", "content": "Weather in Mumbai?"}
    assert wire_messages[1] == {
        "role": "assistant",
        "content": [
            {
                "type": "tool_use",
                "id": "toolu_1",
                "name": "get_weather",
                "input": {"latitude": 19.08, "longitude": 72.88},
            }
        ],
    }
    assert wire_messages[2] == {
        "role": "user",
        "content": [
            {"type": "tool_result", "tool_use_id": "toolu_1", "content": '{"temperature_c": 28.0}'}
        ],
    }


def test_generate_batches_consecutive_tool_results_into_one_wire_message():
    payload = {"content": [{"type": "text", "text": "final answer"}], "stop_reason": "end_turn"}
    capture: dict = {}
    client = _client_returning(payload, capture)
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    history = [
        {"role": "user", "content": "Weather and METAR for Mumbai?"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {"id": "toolu_1", "name": "get_weather", "input": {"latitude": 19.08, "longitude": 72.88}},
                {"id": "toolu_2", "name": "get_metar", "input": {"icao": "VABB"}},
            ],
        },
        {"role": "tool", "tool_call_id": "toolu_1", "content": '{"temperature_c": 28.0}'},
        {"role": "tool", "tool_call_id": "toolu_2", "content": '{"flight_category": "VFR"}'},
    ]

    provider.generate(system="sys", history=history, tools=[])

    wire_messages = capture["body"]["messages"]
    assert len(wire_messages) == 3
    assert wire_messages[2] == {
        "role": "user",
        "content": [
            {"type": "tool_result", "tool_use_id": "toolu_1", "content": '{"temperature_c": 28.0}'},
            {"type": "tool_result", "tool_use_id": "toolu_2", "content": '{"flight_category": "VFR"}'},
        ],
    }


def test_generate_can_be_called_twice_on_the_same_instance():
    # Regression test for the critical client-lifecycle bug: chat_turn calls
    # generate() repeatedly on one long-lived provider instance whenever the
    # model requests a tool call. The old code closed self._client in a
    # `finally` at the end of EVERY generate() call, so the second call on
    # any tool-using conversation raised
    # `RuntimeError: Cannot send a request, as the client has been closed.`
    # This test would have failed with that RuntimeError on the old code.
    payload = {"content": [{"type": "text", "text": "ok"}], "stop_reason": "end_turn"}
    client = _client_returning(payload)
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    first = provider.generate(system="sys", history=[{"role": "user", "content": "one"}], tools=[])
    second = provider.generate(system="sys", history=[{"role": "user", "content": "two"}], tools=[])

    assert first.text == "ok"
    assert second.text == "ok"


def test_close_closes_self_owned_client():
    provider = AnthropicLLMProvider(api_key="test-key")
    assert provider._owns_client is True
    assert provider._client.is_closed is False

    provider.close()

    assert provider._client.is_closed is True


def test_close_does_not_close_injected_client():
    payload = {"content": [{"type": "text", "text": "ok"}], "stop_reason": "end_turn"}
    injected_client = _client_returning(payload)
    provider = AnthropicLLMProvider(api_key="test-key", client=injected_client)
    assert provider._owns_client is False

    provider.close()

    assert injected_client.is_closed is False


def test_generate_raises_on_http_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": "boom"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    with pytest.raises(httpx.HTTPStatusError):
        provider.generate(system="sys", history=[{"role": "user", "content": "hi"}], tools=[])


def test_generate_retries_on_transient_failure_then_succeeds(monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)
    calls = {"count": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["count"] += 1
        if calls["count"] < 3:
            return httpx.Response(503)
        return httpx.Response(200, json={"content": [{"type": "text", "text": "ok"}], "stop_reason": "end_turn"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    turn = provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])

    assert turn.text == "ok"
    assert calls["count"] == 3


def test_generate_does_not_retry_on_permanent_client_error(monkeypatch):
    slept = []
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: slept.append(s))

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "invalid api key"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="bad-key", client=client)

    with pytest.raises(httpx.HTTPStatusError):
        provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])

    assert slept == []
