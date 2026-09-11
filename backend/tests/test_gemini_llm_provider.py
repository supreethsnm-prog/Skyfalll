import json

import httpx
import pytest

from app.config import get_settings
from app.providers.gemini import GeminiLLMProvider
from app.providers.llm import ToolSpec


def _client_returning(payload: dict, capture: dict | None = None) -> httpx.Client:
    def handler(request: httpx.Request) -> httpx.Response:
        if capture is not None:
            capture["body"] = json.loads(request.content)
            capture["headers"] = dict(request.headers)
            capture["url"] = str(request.url)
        return httpx.Response(200, json=payload)

    return httpx.Client(transport=httpx.MockTransport(handler))


_TEXT_PAYLOAD = {
    "candidates": [
        {"content": {"parts": [{"text": "Hello there."}], "role": "model"}, "finishReason": "STOP"}
    ]
}

_TOOL_PAYLOAD = {
    "candidates": [
        {
            "content": {
                "parts": [
                    {
                        "functionCall": {
                            "name": "get_weather",
                            "args": {"latitude": 19.05, "longitude": 72.87},
                        },
                        "thoughtSignature": "opaque-blob-we-should-ignore",
                    }
                ],
                "role": "model",
            },
            "finishReason": "STOP",
            "finishMessage": "Model generated function call(s).",
        }
    ]
}


def test_raises_without_api_key(monkeypatch):
    # A real GEMINI_API_KEY lives in backend/.env on dev machines. Deleting it
    # from os.environ isn't enough on its own: pydantic-settings falls back to
    # reading the dotenv file directly whenever the var is absent from the
    # environment, which would silently reintroduce the real key here. An
    # empty-but-present env var takes precedence over that dotenv fallback,
    # so set it to "" rather than deleting it.
    monkeypatch.setenv("GEMINI_API_KEY", "")
    get_settings.cache_clear()
    try:
        with pytest.raises(ValueError, match="GEMINI_API_KEY"):
            GeminiLLMProvider(api_key=None)
    finally:
        get_settings.cache_clear()


def test_generate_returns_text_turn():
    capture: dict = {}
    provider = GeminiLLMProvider(
        api_key="test-key", model="gemini-2.5-flash", client=_client_returning(_TEXT_PAYLOAD, capture)
    )

    turn = provider.generate(
        system="You are a test assistant.",
        history=[{"role": "user", "content": "Hi"}],
        tools=[],
    )

    assert turn.text == "Hello there."
    assert turn.tool_calls == []
    assert turn.stop_reason == "end_turn"
    # Auth must be a header, never a query param — secrets don't belong in URLs.
    assert capture["headers"]["x-goog-api-key"] == "test-key"
    assert "test-key" not in capture["url"]
    assert "gemini-2.5-flash:generateContent" in capture["url"]
    assert capture["body"]["systemInstruction"] == {"parts": [{"text": "You are a test assistant."}]}
    assert capture["body"]["contents"] == [{"role": "user", "parts": [{"text": "Hi"}]}]


def test_generate_detects_tool_call_despite_stop_finish_reason():
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TOOL_PAYLOAD))

    turn = provider.generate(system="s", history=[{"role": "user", "content": "weather?"}], tools=[])

    # Gemini reports finishReason STOP even for function calls — detection must
    # be by the presence of functionCall parts, not by finishReason.
    assert turn.stop_reason == "tool_use"
    assert len(turn.tool_calls) == 1
    call = turn.tool_calls[0]
    assert call.name == "get_weather"
    assert call.input == {"latitude": 19.05, "longitude": 72.87}
    assert call.id  # synthesized locally; Gemini supplies no id


def test_generate_maps_max_tokens_finish_reason():
    payload = {
        "candidates": [
            {"content": {"parts": [{"text": "trunc"}], "role": "model"}, "finishReason": "MAX_TOKENS"}
        ]
    }
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(payload))
    turn = provider.generate(system="s", history=[{"role": "user", "content": "x"}], tools=[])
    assert turn.stop_reason == "max_tokens"


def test_translates_tool_specs_to_function_declarations():
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))
    tools = [
        ToolSpec(
            name="get_weather",
            description="Get current weather.",
            input_schema={"type": "object", "properties": {"latitude": {"type": "number"}}},
        )
    ]

    provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=tools)

    assert capture["body"]["tools"] == [
        {
            "functionDeclarations": [
                {
                    "name": "get_weather",
                    "description": "Get current weather.",
                    "parameters": {"type": "object", "properties": {"latitude": {"type": "number"}}},
                }
            ]
        }
    ]


def test_omits_tools_key_when_no_tools_given():
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))
    provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])
    assert "tools" not in capture["body"]


def test_translates_assistant_tool_call_and_tool_result_history():
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))

    history = [
        {"role": "user", "content": "Weather in Mumbai?"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {"id": "c1", "name": "get_weather", "input": {"latitude": 19.05, "longitude": 72.87}}
            ],
        },
        {"role": "tool", "tool_call_id": "c1", "name": "get_weather", "content": '{"temperature_c": 26.2}'},
    ]

    provider.generate(system="s", history=history, tools=[])

    contents = capture["body"]["contents"]
    assert contents[0] == {"role": "user", "parts": [{"text": "Weather in Mumbai?"}]}
    # assistant -> "model" role, tool_call -> functionCall (id dropped, Gemini has none)
    assert contents[1] == {
        "role": "model",
        "parts": [
            {"functionCall": {"name": "get_weather", "args": {"latitude": 19.05, "longitude": 72.87}}}
        ],
    }
    # tool result -> user-role functionResponse, matched by NAME
    assert contents[2] == {
        "role": "user",
        "parts": [{"functionResponse": {"name": "get_weather", "response": {"temperature_c": 26.2}}}],
    }


def test_tool_result_name_resolved_from_earlier_call_when_absent():
    """A history round-tripped by an older client may omit `name` on tool entries."""
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))

    history = [
        {"role": "user", "content": "q"},
        {"role": "assistant", "content": "", "tool_calls": [{"id": "c9", "name": "get_metar", "input": {}}]},
        {"role": "tool", "tool_call_id": "c9", "content": "{}"},  # no "name" key
    ]

    provider.generate(system="s", history=history, tools=[])

    assert capture["body"]["contents"][2]["parts"][0]["functionResponse"]["name"] == "get_metar"


def test_non_object_tool_result_is_wrapped():
    """execute_tool returns a JSON string that may encode a LIST (list_alerts,
    list_pfz_zones). Gemini requires functionResponse.response to be an object."""
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))

    history = [
        {"role": "user", "content": "alerts?"},
        {"role": "assistant", "content": "", "tool_calls": [{"id": "c1", "name": "list_alerts", "input": {}}]},
        {"role": "tool", "tool_call_id": "c1", "name": "list_alerts", "content": '[{"severity": "ALERT"}]'},
    ]

    provider.generate(system="s", history=history, tools=[])

    resp = capture["body"]["contents"][2]["parts"][0]["functionResponse"]["response"]
    assert resp == {"result": [{"severity": "ALERT"}]}


def test_batches_consecutive_tool_results_into_one_message():
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))

    history = [
        {"role": "user", "content": "q"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {"id": "c1", "name": "get_weather", "input": {}},
                {"id": "c2", "name": "get_metar", "input": {}},
            ],
        },
        {"role": "tool", "tool_call_id": "c1", "name": "get_weather", "content": "{}"},
        {"role": "tool", "tool_call_id": "c2", "name": "get_metar", "content": "{}"},
    ]

    provider.generate(system="s", history=history, tools=[])

    contents = capture["body"]["contents"]
    assert len(contents) == 3
    assert len(contents[2]["parts"]) == 2


def test_unknown_role_raises_value_error():
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD))
    with pytest.raises(ValueError, match="Unknown history role"):
        provider.generate(system="s", history=[{"role": "system", "content": "x"}], tools=[])


def test_generate_can_be_called_twice_on_a_self_owned_client():
    """Regression guard: generate() must never close the client — chat_turn calls
    it repeatedly on one instance whenever the model requests a tool."""
    provider = GeminiLLMProvider(api_key="k")
    provider._client = _client_returning(_TEXT_PAYLOAD)  # self-owned flag stays True
    assert provider._owns_client is True

    assert provider.generate(system="s", history=[{"role": "user", "content": "1"}], tools=[]).text
    assert provider.generate(system="s", history=[{"role": "user", "content": "2"}], tools=[]).text

    provider.close()
    assert provider._client.is_closed


def test_close_does_not_close_an_injected_client():
    client = _client_returning(_TEXT_PAYLOAD)
    provider = GeminiLLMProvider(api_key="k", client=client)
    provider.close()
    assert not client.is_closed


def test_generate_raises_on_http_error(monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"error": "rate limited"})

    provider = GeminiLLMProvider(api_key="k", client=httpx.Client(transport=httpx.MockTransport(handler)))
    with pytest.raises(httpx.HTTPStatusError):
        provider.generate(system="s", history=[{"role": "user", "content": "x"}], tools=[])


def test_same_name_parallel_tool_results_preserve_call_order():
    """Gemini has no call ids — a functionResponse is matched to its
    functionCall by name alone. When one turn calls the SAME tool twice
    (e.g. "compare weather in Mumbai and Delhi"), both responses carry an
    identical name, and disambiguation depends entirely on returning the
    responses in the same order the calls were made.

    Verified live against the real Gemini API during planning: prompting
    gemini-2.5-flash to call get_weather for two different coordinates in
    one turn produced two functionCall parts in a stable order, and
    sending back functionResponse parts in that same order was correctly
    attributed by the model (Mumbai's response was not swapped with
    Delhi's). This test locks in the CODE-LEVEL half of that behavior:
    _translate_history must never reorder tool-role history entries
    relative to the order they were appended in.
    """
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))

    history = [
        {"role": "user", "content": "Compare weather in Mumbai and Delhi"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {"id": "c1", "name": "get_weather", "input": {"latitude": 19.05, "longitude": 72.87}},
                {"id": "c2", "name": "get_weather", "input": {"latitude": 28.6, "longitude": 77.2}},
            ],
        },
        # Order matters: Mumbai's result must stay first, Delhi's second,
        # even though both entries share the same tool name.
        {"role": "tool", "tool_call_id": "c1", "name": "get_weather", "content": '{"temperature_c": 99.0}'},
        {"role": "tool", "tool_call_id": "c2", "name": "get_weather", "content": '{"temperature_c": 11.0}'},
    ]

    provider.generate(system="s", history=history, tools=[])

    contents = capture["body"]["contents"]
    # Both functionCall parts land in the assistant/model turn, in request order.
    model_turn = contents[1]
    assert [p["functionCall"]["args"] for p in model_turn["parts"]] == [
        {"latitude": 19.05, "longitude": 72.87},
        {"latitude": 28.6, "longitude": 77.2},
    ]
    # Both functionResponse parts batch into one message, in the SAME order
    # as the calls — this is the exact property Gemini relies on to
    # disambiguate two identically-named results.
    response_turn = contents[2]
    responses = [p["functionResponse"]["response"] for p in response_turn["parts"]]
    assert responses == [{"temperature_c": 99.0}, {"temperature_c": 11.0}]


def test_generate_retries_on_transient_failure_then_succeeds(monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)
    calls = {"count": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["count"] += 1
        if calls["count"] < 3:
            return httpx.Response(503)
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"parts": [{"text": "ok"}], "role": "model"}, "finishReason": "STOP"}]},
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = GeminiLLMProvider(api_key="test-key", client=client)

    turn = provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])

    assert turn.text == "ok"
    assert calls["count"] == 3


def test_generate_does_not_retry_on_permanent_client_error(monkeypatch):
    slept = []
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: slept.append(s))

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": "bad request"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = GeminiLLMProvider(api_key="bad-key", client=client)

    with pytest.raises(httpx.HTTPStatusError):
        provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])

    assert slept == []


def test_synthesized_tool_call_ids_are_unique_across_generate_calls():
    """A synthesized id that resets to gemini-0/gemini-1/... on every
    generate() call would repeat across rounds of one conversation (round
    1 and round 2 could both mint "gemini-0"). Nothing currently depends
    on cross-round uniqueness (the server always attaches an explicit
    "name" to tool-role entries, so the id->name fallback is never
    consulted in practice) — but it's a latent trap for any future code
    that correlates by tool-call id across a whole conversation, so ids
    must be unique for the life of the process, not just within one call.
    """
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TOOL_PAYLOAD))

    turn1 = provider.generate(system="s", history=[{"role": "user", "content": "a"}], tools=[])
    turn2 = provider.generate(system="s", history=[{"role": "user", "content": "b"}], tools=[])

    ids_seen = {call.id for call in turn1.tool_calls} | {call.id for call in turn2.tool_calls}
    assert len(ids_seen) == len(turn1.tool_calls) + len(turn2.tool_calls)


def test_generate_extracts_thought_signature_and_call_id():
    payload = {
        "candidates": [
            {
                "content": {
                    "parts": [
                        {
                            "functionCall": {
                                "name": "geocode",
                                "args": {"query": "Delhi"},
                                "id": "call_123",
                            },
                            "thoughtSignature": "test-signature-blob",
                        }
                    ],
                    "role": "model",
                },
                "finishReason": "STOP",
            }
        ]
    }
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(payload))
    turn = provider.generate(system="s", history=[{"role": "user", "content": "Delhi"}], tools=[])
    assert len(turn.tool_calls) == 1
    call = turn.tool_calls[0]
    assert call.id == "call_123"
    assert call.name == "geocode"
    assert call.thought_signature == "test-signature-blob"


def test_translate_history_preserves_thought_signature():
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))

    history = [
        {"role": "user", "content": "weather in Delhi"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {
                    "id": "call_123",
                    "name": "geocode",
                    "input": {"query": "Delhi"},
                    "thought_signature": "test-signature-blob",
                }
            ],
        },
        {
            "role": "tool",
            "tool_call_id": "call_123",
            "name": "geocode",
            "content": '{"lat": 28.6, "lon": 77.2}',
        },
    ]

    provider.generate(system="s", history=history, tools=[])
    model_parts = capture["body"]["contents"][1]["parts"]
    assert len(model_parts) == 1
    assert model_parts[0]["thoughtSignature"] == "test-signature-blob"
    assert model_parts[0]["functionCall"] == {"name": "geocode", "args": {"query": "Delhi"}}

