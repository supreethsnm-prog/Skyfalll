# Gemini LLM Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `GeminiLLMProvider` implementing the existing `LLMProvider` Protocol, plus provider selection, so `/chat` works with a Google Gemini API key (the only LLM key currently configured — `ANTHROPIC_API_KEY` is empty, which means `/chat` is presently non-functional).

**Architecture:** The `LLMProvider` Protocol (`app/providers/llm.py`) and its canonical `ToolSpec`/`ToolCall`/`LLMTurn` dataclasses already exist precisely so a second vendor is a new adapter, not a rewrite. This plan adds that adapter plus a small factory that picks a provider from configuration.

**Tech Stack:** Same as the rest of the backend — FastAPI, SQLAlchemy, raw `httpx` (no vendor SDK, consistent with every other provider here).

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md (§4's LLM bullet: "No model name is hardcoded... A currently-real, verified model is selected at the implementation sprint for this provider — the abstraction makes the choice a config value, not an architecture decision.")

## Verified API facts (probed live against the real Gemini API during planning — use these exact shapes, do not infer from memory)

- Endpoint: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Auth: header `x-goog-api-key: <key>` (verified HTTP 200). A `?key=` query param also works but **must not be used** — secrets do not belong in URLs (they leak into logs and proxies).
- System prompt: `"systemInstruction": {"parts": [{"text": "..."}]}` — NOT a top-level `system` string like Anthropic.
- Tools: `"tools": [{"functionDeclarations": [{"name", "description", "parameters"}]}]` — note `parameters` (not Anthropic's `input_schema`), and all declarations nest inside ONE array element.
- Messages: `"contents": [{"role": "user"|"model", "parts": [...]}]` — the assistant role is `"model"`, not `"assistant"`.
- Tool call in response: `candidates[0].content.parts[].functionCall = {"name", "args"}` — **there is no `id` field.** Gemini matches a result to a call by function NAME.
- Tool result sent back: a **`user`**-role message containing `{"functionResponse": {"name": ..., "response": {...}}}`. `response` must be a JSON **object**.
- `finishReason` is `"STOP"` even when the model emitted a function call (with `finishMessage: "Model generated function call(s)."`). Tool calls must therefore be detected by the PRESENCE of `functionCall` parts, never by `finishReason`.
- Truncation surfaces as `finishReason: "MAX_TOKENS"`.
- Gemini 2.5 includes an opaque `thoughtSignature` alongside `functionCall`. **Verified live that a full round trip succeeds without echoing it back** (HTTP 200, correct tool-grounded answer), so this adapter drops it.
- A Hindi-language query was verified to produce a correct tool call, confirming multilingual behaviour at the model level.
- Model `gemini-2.5-flash` verified available and working.

## Global Constraints

- Provider abstraction pattern (established in every prior sprint): `Protocol` + canonical `@dataclass` + a concrete class taking `client: httpx.Client | None = None`, setting `self._owns_client = client is None`.
- **Client lifecycle (learned the hard way last sprint):** `generate()` must NEVER close the client — `chat_turn` calls `generate()` repeatedly on one instance. Closing belongs in an explicit `close()` that only closes a self-owned client. See `app/providers/anthropic.py:121-130` for the exact pattern to mirror.
- No model name hardcoded: the Gemini model ID is a config value (`Settings.gemini_model`), never a literal in provider logic.
- No secrets in URLs, ever (use the `x-goog-api-key` header).
- Tests must never make real network calls — use `httpx.MockTransport` with the real captured shapes above.

---

### Task 1: GeminiLLMProvider

**Files:**
- Modify: `backend/app/config.py`
- Create: `backend/app/providers/gemini.py`
- Modify: `backend/.env.example`
- Test: `backend/tests/test_gemini_llm_provider.py`

**Interfaces:**
- Consumes: `ToolSpec`, `ToolCall`, `LLMTurn` from `app/providers/llm.py` (unchanged); `Settings.gemini_api_key` / `gemini_model` / `gemini_max_tokens`.
- Produces: `GeminiLLMProvider` satisfying `LLMProvider` — `generate(self, system: str, history: list[dict], tools: list[ToolSpec]) -> LLMTurn` plus `close()`.
- Canonical history shape consumed (same as the Anthropic adapter): `{"role": "user", "content": str}`, `{"role": "assistant", "content": str, "tool_calls": [{"id","name","input"}]}`, `{"role": "tool", "tool_call_id": str, "content": str, "name": str (optional)}`.

- [ ] **Step 1: Add Gemini settings**

In `backend/app/config.py`, add to `Settings` immediately after the existing `anthropic_max_tokens` line:

```python
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-2.5-flash"
    gemini_max_tokens: int = 1024
```

- [ ] **Step 2: Document them in `.env.example`**

Append to `backend/.env.example`:

```
GEMINI_API_KEY=
GEMINI_MODEL=gemini-2.5-flash
```

- [ ] **Step 3: Write the failing tests**

Create `backend/tests/test_gemini_llm_provider.py`:

```python
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
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
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


def test_generate_raises_on_http_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"error": "rate limited"})

    provider = GeminiLLMProvider(api_key="k", client=httpx.Client(transport=httpx.MockTransport(handler)))
    with pytest.raises(httpx.HTTPStatusError):
        provider.generate(system="s", history=[{"role": "user", "content": "x"}], tools=[])
```

- [ ] **Step 4: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gemini_llm_provider.py -v`
Expected: FAIL — `app.providers.gemini` does not exist.

- [ ] **Step 5: Write `app/providers/gemini.py`**

```python
"""Google Gemini (generativelanguage) adapter for the LLMProvider abstraction.

Gemini's wire format differs from Anthropic's in ways that all live in this
file, which is the point of the LLMProvider Protocol:
  - the assistant role is called "model"
  - tool schemas are `functionDeclarations` with `parameters`, not `input_schema`
  - function calls carry NO id; a result is matched to its call by NAME
  - `finishReason` is "STOP" even when the model emitted a function call, so
    tool use is detected by the presence of functionCall parts
  - `functionResponse.response` must be a JSON object, never a bare list

Like app/providers/anthropic.py, this provider is never wrapped in a cache —
see app/chat/service.py's module docstring.
"""

import json

import httpx

from app.config import get_settings
from app.providers.llm import LLMTurn, ToolCall, ToolSpec

GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"


def _as_response_object(content: str) -> dict:
    """Gemini requires functionResponse.response to be a JSON object.

    execute_tool returns a JSON string that may encode a list (list_alerts,
    list_pfz_zones) or a scalar, so anything that isn't already an object is
    wrapped rather than sent as-is.
    """
    try:
        parsed = json.loads(content)
    except (TypeError, ValueError):
        return {"result": content}
    if isinstance(parsed, dict):
        return parsed
    return {"result": parsed}


def _translate_history(history: list[dict]) -> list[dict]:
    contents: list[dict] = []
    # Gemini matches a tool result to its call by name, so remember the name
    # each call id was issued under for histories that omit it.
    id_to_name: dict[str, str] = {}

    for entry in history:
        role = entry["role"]
        if role == "user":
            contents.append({"role": "user", "parts": [{"text": entry["content"]}]})
        elif role == "assistant":
            parts: list[dict] = []
            if entry.get("content"):
                parts.append({"text": entry["content"]})
            for call in entry.get("tool_calls") or []:
                id_to_name[call["id"]] = call["name"]
                parts.append({"functionCall": {"name": call["name"], "args": call["input"]}})
            if not parts:
                parts.append({"text": ""})
            contents.append({"role": "model", "parts": parts})
        elif role == "tool":
            name = entry.get("name") or id_to_name.get(entry.get("tool_call_id", ""))
            if not name:
                raise ValueError(
                    f"Cannot resolve a function name for tool result "
                    f"{entry.get('tool_call_id')!r} — no 'name' on the entry and no "
                    f"matching tool call earlier in the history."
                )
            part = {
                "functionResponse": {
                    "name": name,
                    "response": _as_response_object(entry["content"]),
                }
            }
            if (
                contents
                and contents[-1]["role"] == "user"
                and any("functionResponse" in p for p in contents[-1]["parts"])
            ):
                contents[-1]["parts"].append(part)
            else:
                contents.append({"role": "user", "parts": [part]})
        else:
            raise ValueError(f"Unknown history role: {role!r}")
    return contents


def _translate_tools(tools: list[ToolSpec]) -> list[dict]:
    return [
        {
            "functionDeclarations": [
                {
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.input_schema,
                }
                for tool in tools
            ]
        }
    ]


class GeminiLLMProvider:
    def __init__(
        self,
        api_key: str | None = None,
        model: str | None = None,
        base_url: str = GEMINI_BASE_URL,
        client: httpx.Client | None = None,
    ):
        settings = get_settings()
        self._api_key = api_key if api_key is not None else settings.gemini_api_key
        if not self._api_key:
            raise ValueError(
                "GEMINI_API_KEY is not set. Set it in backend/.env or as an "
                "environment variable to enable chat."
            )
        self._model = model or settings.gemini_model
        self._max_tokens = settings.gemini_max_tokens
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=30.0)

    def generate(self, system: str, history: list[dict], tools: list[ToolSpec]) -> LLMTurn:
        body: dict = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": _translate_history(history),
            "generationConfig": {"maxOutputTokens": self._max_tokens},
        }
        if tools:
            body["tools"] = _translate_tools(tools)

        response = self._client.post(
            f"{self._base_url}/models/{self._model}:generateContent",
            headers={
                # Header auth, never a ?key= query param: secrets must not
                # appear in URLs, where they leak into logs and proxies.
                "x-goog-api-key": self._api_key,
                "content-type": "application/json",
            },
            json=body,
        )
        response.raise_for_status()
        payload = response.json()

        candidates = payload.get("candidates") or []
        if not candidates:
            return LLMTurn(text=None, tool_calls=[], stop_reason="end_turn")

        candidate = candidates[0]
        parts = (candidate.get("content") or {}).get("parts") or []

        text_parts: list[str] = []
        tool_calls: list[ToolCall] = []
        for index, part in enumerate(parts):
            if "text" in part:
                text_parts.append(part["text"])
            elif "functionCall" in part:
                function_call = part["functionCall"]
                tool_calls.append(
                    ToolCall(
                        # Gemini supplies no call id; synthesize one that is
                        # unique within this turn for our canonical format.
                        id=f"gemini-{index}",
                        name=function_call["name"],
                        input=function_call.get("args") or {},
                    )
                )

        if tool_calls:
            stop_reason = "tool_use"
        elif candidate.get("finishReason") == "MAX_TOKENS":
            stop_reason = "max_tokens"
        else:
            stop_reason = "end_turn"

        return LLMTurn(
            text="".join(text_parts) or None,
            tool_calls=tool_calls,
            stop_reason=stop_reason,
        )

    def close(self) -> None:
        """Close the underlying HTTP client, but only if this provider created it.

        Never call this from generate(): chat_turn calls generate() repeatedly
        on one instance whenever the model requests a tool.
        """
        if self._owns_client:
            self._client.close()
```

- [ ] **Step 6: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gemini_llm_provider.py -v`
Expected: PASS, all 13 tests.

- [ ] **Step 7: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: 86 existing + 13 new all PASS.

- [ ] **Step 8: Commit**

```bash
git add backend/app/config.py backend/app/providers/gemini.py backend/.env.example backend/tests/test_gemini_llm_provider.py
git commit -m "feat: add GeminiLLMProvider adapter for the LLMProvider abstraction"
```

---

### Task 2: Provider selection and wiring

**Files:**
- Modify: `backend/app/config.py`
- Create: `backend/app/providers/factory.py`
- Modify: `backend/app/chat/service.py`
- Modify: `backend/app/main.py`
- Modify: `backend/.env.example`
- Test: `backend/tests/test_llm_provider_factory.py`

**Interfaces:**
- Consumes: `AnthropicLLMProvider` (`app/providers/anthropic.py`), `GeminiLLMProvider` (Task 1), `Settings`.
- Produces: `build_llm_provider() -> LLMProvider` in `app/providers/factory.py`, used by both `app/chat/service.py`'s default and `app/main.py`'s `get_llm_provider` dependency.

- [ ] **Step 1: Add the selection setting**

In `backend/app/config.py`, add after the Gemini settings from Task 1:

```python
    llm_provider: str = "auto"
```

Append to `backend/.env.example`:

```
# auto | anthropic | gemini  (auto picks whichever API key is configured)
LLM_PROVIDER=auto
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_llm_provider_factory.py`:

```python
import pytest

from app.config import get_settings
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.factory import build_llm_provider
from app.providers.gemini import GeminiLLMProvider


@pytest.fixture
def clean_settings(monkeypatch):
    """Isolate provider selection from ambient env and the settings cache."""
    for var in ("ANTHROPIC_API_KEY", "GEMINI_API_KEY", "LLM_PROVIDER"):
        monkeypatch.delenv(var, raising=False)
    get_settings.cache_clear()
    yield monkeypatch
    get_settings.cache_clear()


def _built(monkeypatch, **env):
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    get_settings.cache_clear()
    provider = build_llm_provider()
    provider.close()
    return provider


def test_auto_selects_gemini_when_only_gemini_key_set(clean_settings):
    provider = _built(clean_settings, GEMINI_API_KEY="g-key")
    assert isinstance(provider, GeminiLLMProvider)


def test_auto_selects_anthropic_when_only_anthropic_key_set(clean_settings):
    provider = _built(clean_settings, ANTHROPIC_API_KEY="a-key")
    assert isinstance(provider, AnthropicLLMProvider)


def test_explicit_choice_wins_over_auto_detection(clean_settings):
    provider = _built(clean_settings, ANTHROPIC_API_KEY="a-key", GEMINI_API_KEY="g-key", LLM_PROVIDER="gemini")
    assert isinstance(provider, GeminiLLMProvider)


def test_explicit_choice_is_case_insensitive(clean_settings):
    provider = _built(clean_settings, GEMINI_API_KEY="g-key", LLM_PROVIDER="Gemini")
    assert isinstance(provider, GeminiLLMProvider)


def test_no_keys_configured_raises_naming_both_env_vars(clean_settings):
    get_settings.cache_clear()
    with pytest.raises(ValueError) as excinfo:
        build_llm_provider()
    message = str(excinfo.value)
    assert "ANTHROPIC_API_KEY" in message
    assert "GEMINI_API_KEY" in message


def test_unknown_provider_name_raises(clean_settings):
    clean_settings.setenv("LLM_PROVIDER", "llama")
    get_settings.cache_clear()
    with pytest.raises(ValueError, match="llama"):
        build_llm_provider()
```

- [ ] **Step 3: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_llm_provider_factory.py -v`
Expected: FAIL — `app.providers.factory` does not exist.

- [ ] **Step 4: Create `app/providers/factory.py`**

```python
"""Selects which LLM vendor backs the chat endpoint.

The choice is configuration, not architecture: every provider here satisfies
the same LLMProvider Protocol, so adding a vendor means adding an adapter and
one branch below.
"""

from app.config import get_settings
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.gemini import GeminiLLMProvider
from app.providers.llm import LLMProvider

_PROVIDERS = {
    "anthropic": AnthropicLLMProvider,
    "gemini": GeminiLLMProvider,
}


def build_llm_provider() -> LLMProvider:
    settings = get_settings()
    choice = (settings.llm_provider or "auto").strip().lower()

    if choice != "auto":
        provider_class = _PROVIDERS.get(choice)
        if provider_class is None:
            raise ValueError(
                f"Unknown LLM_PROVIDER {choice!r}. Use 'auto', "
                f"{', '.join(repr(name) for name in _PROVIDERS)}."
            )
        return provider_class()

    if settings.anthropic_api_key:
        return AnthropicLLMProvider()
    if settings.gemini_api_key:
        return GeminiLLMProvider()

    raise ValueError(
        "No LLM API key configured. Set ANTHROPIC_API_KEY or GEMINI_API_KEY "
        "in backend/.env to enable chat."
    )
```

- [ ] **Step 5: Run them, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_llm_provider_factory.py -v`
Expected: PASS, all 6 tests.

- [ ] **Step 6: Wire the factory into `app/chat/service.py`**

Replace the import:

```python
from app.providers.anthropic import AnthropicLLMProvider
```

with:

```python
from app.providers.factory import build_llm_provider
```

and in `chat_turn`, replace:

```python
    llm = provider or AnthropicLLMProvider()
```

with:

```python
    llm = provider or build_llm_provider()
```

- [ ] **Step 7: Carry the tool name into tool-result history entries**

Gemini matches a tool result to its call by function NAME (it has no call ids), so the canonical history entry must carry it. In `app/chat/service.py`'s `chat_turn`, change the tool-result append from:

```python
                    conversation.append(
                        {"role": "tool", "tool_call_id": call.id, "content": result}
                    )
```

to:

```python
                    conversation.append(
                        {
                            "role": "tool",
                            "tool_call_id": call.id,
                            # Gemini matches a result to its call by name, not id.
                            "name": call.name,
                            "content": result,
                        }
                    )
```

This is additive — `app/providers/anthropic.py`'s translation reads only `tool_call_id` and `content`, so the extra key is ignored there.

- [ ] **Step 8: Wire the factory into `app/main.py`**

Replace the import `from app.providers.anthropic import AnthropicLLMProvider` with `from app.providers.factory import build_llm_provider`, and inside `get_llm_provider` replace `provider = AnthropicLLMProvider()` with `provider = build_llm_provider()`. Leave the surrounding `try/except ValueError -> HTTPException(503)` and the generator/`finally: provider.close()` structure exactly as they are — the factory raises the same `ValueError` type on a missing key, so the 503 path still works unchanged.

- [ ] **Step 9: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: everything PASSES. Note `tests/test_chat_endpoint.py::test_chat_endpoint_returns_503_when_api_key_missing` — it must still pass, because the factory raises `ValueError` just like the old direct construction did. If it fails because the machine's `.env` now has a real `GEMINI_API_KEY`, that is a genuine test-isolation bug in that test: fix it by having the test `monkeypatch.delenv` BOTH `ANTHROPIC_API_KEY` and `GEMINI_API_KEY` (plus `get_settings.cache_clear()`), matching the pattern already used in `tests/test_anthropic_llm_provider.py::test_generate_raises_without_api_key`.

- [ ] **Step 10: Commit**

```bash
git add backend/app/config.py backend/app/providers/factory.py backend/app/chat/service.py backend/app/main.py backend/.env.example backend/tests/test_llm_provider_factory.py backend/tests/test_chat_endpoint.py
git commit -m "feat: select LLM provider from config, defaulting to whichever key is set"
```
