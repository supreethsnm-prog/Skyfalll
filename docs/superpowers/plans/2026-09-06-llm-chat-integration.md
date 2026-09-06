# LLM Chat Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give WeatherGPT its actual conversational layer — an `LLMProvider` abstraction backed by the Anthropic Messages API, a tool registry wrapping the five existing query-path services (weather, geocoding, METAR, alerts, marine PFZ zones), an agentic tool-calling loop, and a `POST /chat` endpoint.

**Architecture:** Everything built so far (SACHET alerts, Open-Meteo weather, Nominatim geocoding, aviationweather.gov METAR, INCOIS marine) exists to be *read*, never independently re-derived by an LLM — per the spec's grounding principle (§1), the model interprets natural language and calls tools; it never states a weather/alert fact from memory. This plan wires that up: a provider-abstracted LLM client, a small tool registry whose handlers call the *existing* service functions (never raw providers, so every existing caching/response-hygiene guarantee is inherited for free), and a loop that alternates LLM turns with tool execution until the model produces a final answer or a safety cap is hit.

**Tech Stack:** Same as the rest of the backend — FastAPI, SQLAlchemy, httpx (hand-rolled HTTP call to `https://api.anthropic.com/v1/messages`, no new dependency — consistent with every other provider in this codebase using raw httpx rather than a vendor SDK).

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md

## Global Constraints

- Provider abstraction pattern (spec, established in every prior sprint): a `Protocol` + a canonical `@dataclass` (provider-agnostic shape, not the raw wire format) + a concrete provider class with `__init__(self, ..., client: httpx.Client | None = None)`, `self._owns_client = client is None`, closing the client in `finally` only if self-owned.
- Grounding principle (spec §1): the LLM never states a specific fact (a temperature, an alert, an observation) without it coming from a tool call. Tool handlers must call the *existing* service functions (`get_weather`, `geocode_place`, `get_metar`, and the two new ones this plan adds) — never query providers or raw tables directly — so every existing caching and response-hygiene guarantee (no `raw_payload` leakage) is inherited, not re-implemented.
- No model name is hardcoded (spec §4, "LLM" bullet): the Anthropic model ID is a config value (`Settings.anthropic_model`), not a literal baked into provider code.
- Per-call isolation (a lesson repeated three times across the SACHET, weather, and INCOIS marine sprints — see `app/providers/incois.py`'s history): a single malformed or failing tool call must produce an in-band error result the LLM can react to, never an uncaught exception that crashes the whole chat turn.
- LLM responses are a fourth, new pattern distinct from the three caching patterns already in this codebase (scheduled-ingestion, cache-with-TTL, permanent-cache): a chat reply is query-time-only and is **never** cached — each turn is a fresh generation. Document this explicitly in `app/chat/service.py`'s module docstring, cross-referencing the other three patterns the way every prior sprint's ingestion/service module has.
- Response hygiene: no endpoint or tool result may include a provider's `raw_payload` field. Tool handlers get this for free by calling the existing service functions, which already strip it.

---

### Task 1: Anthropic-backed LLM provider

**Files:**
- Modify: `backend/app/config.py`
- Create: `backend/app/providers/llm.py`
- Create: `backend/app/providers/anthropic.py`
- Modify: `backend/.env.example`
- Test: `backend/tests/test_anthropic_llm_provider.py`

**Interfaces:**
- Produces: `ToolSpec(name: str, description: str, input_schema: dict)`, `ToolCall(id: str, name: str, input: dict)`, `LLMTurn(text: str | None, tool_calls: list[ToolCall], stop_reason: str)` dataclasses in `app/providers/llm.py`; `LLMProvider` Protocol with `generate(self, system: str, history: list[dict], tools: list[ToolSpec]) -> LLMTurn`; `AnthropicLLMProvider` implementing it in `app/providers/anthropic.py`.
- `history` canonical shape (provider-agnostic, defined here, consumed by Task 3): a list of plain dicts, one of:
  - `{"role": "user", "content": "<text>"}`
  - `{"role": "assistant", "content": "<text or empty string>", "tool_calls": [{"id": "...", "name": "...", "input": {...}}, ...]}` (the `tool_calls` list is always plain dicts with those three keys, never `ToolCall` instances — this keeps the shape stable across a client round-trip, where a re-submitted history has already gone through JSON and lost any dataclass identity)
  - `{"role": "tool", "tool_call_id": "...", "content": "<string>"}`
- Consumes: `Settings.anthropic_api_key: str | None` and `Settings.anthropic_model: str` from `app/config.py`.

- [ ] **Step 1: Add Anthropic settings**

Modify `backend/app/config.py`'s `Settings` class to add two fields, right after `database_url`:

```python
    anthropic_api_key: str | None = None
    anthropic_model: str = "claude-sonnet-5"
```

- [ ] **Step 2: Document the new settings in `.env.example`**

Append to `backend/.env.example`:

```
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=claude-sonnet-5
```

- [ ] **Step 3: Write `app/providers/llm.py`**

```python
from dataclasses import dataclass, field
from typing import Protocol


@dataclass
class ToolSpec:
    name: str
    description: str
    input_schema: dict


@dataclass
class ToolCall:
    id: str
    name: str
    input: dict


@dataclass
class LLMTurn:
    text: str | None
    tool_calls: list[ToolCall] = field(default_factory=list)
    stop_reason: str = "end_turn"


class LLMProvider(Protocol):
    def generate(
        self, system: str, history: list[dict], tools: list[ToolSpec]
    ) -> LLMTurn: ...
```

- [ ] **Step 4: Write the failing tests for `AnthropicLLMProvider`**

Create `backend/tests/test_anthropic_llm_provider.py`:

```python
import httpx
import pytest

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


def test_generate_raises_without_api_key():
    with pytest.raises(ValueError, match="ANTHROPIC_API_KEY"):
        AnthropicLLMProvider(api_key=None)


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


def test_generate_raises_on_http_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": "boom"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    with pytest.raises(httpx.HTTPStatusError):
        provider.generate(system="sys", history=[{"role": "user", "content": "hi"}], tools=[])
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest tests/test_anthropic_llm_provider.py -v` (from `backend/`)
Expected: FAIL — `app.providers.anthropic` does not exist yet.

- [ ] **Step 6: Write `app/providers/anthropic.py`**

```python
"""Anthropic Messages API adapter for the LLMProvider abstraction.

Unlike every provider elsewhere in this codebase, this one is never
wrapped in a caching layer (see app/chat/service.py's module docstring
for why) — every call this provider makes is live, on every chat turn.
"""

import json

import httpx

from app.config import get_settings
from app.providers.llm import LLMTurn, ToolCall, ToolSpec

ANTHROPIC_BASE_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"


def _translate_history(history: list[dict]) -> list[dict]:
    wire_messages: list[dict] = []
    for entry in history:
        role = entry["role"]
        if role == "user":
            wire_messages.append({"role": "user", "content": entry["content"]})
        elif role == "assistant":
            tool_calls = entry.get("tool_calls") or []
            if not tool_calls:
                wire_messages.append({"role": "assistant", "content": entry.get("content") or ""})
                continue
            content_blocks = []
            if entry.get("content"):
                content_blocks.append({"type": "text", "text": entry["content"]})
            for call in tool_calls:
                content_blocks.append(
                    {
                        "type": "tool_use",
                        "id": call["id"],
                        "name": call["name"],
                        "input": call["input"],
                    }
                )
            wire_messages.append({"role": "assistant", "content": content_blocks})
        elif role == "tool":
            result_block = {
                "type": "tool_result",
                "tool_use_id": entry["tool_call_id"],
                "content": entry["content"],
            }
            if wire_messages and wire_messages[-1]["role"] == "user" and isinstance(
                wire_messages[-1]["content"], list
            ):
                wire_messages[-1]["content"].append(result_block)
            else:
                wire_messages.append({"role": "user", "content": [result_block]})
        else:
            raise ValueError(f"Unknown history role: {role!r}")
    return wire_messages


def _translate_tools(tools: list[ToolSpec]) -> list[dict]:
    return [
        {"name": tool.name, "description": tool.description, "input_schema": tool.input_schema}
        for tool in tools
    ]


class AnthropicLLMProvider:
    def __init__(
        self,
        api_key: str | None = None,
        model: str | None = None,
        base_url: str = ANTHROPIC_BASE_URL,
        client: httpx.Client | None = None,
    ):
        settings = get_settings()
        self._api_key = api_key if api_key is not None else settings.anthropic_api_key
        if not self._api_key:
            raise ValueError(
                "ANTHROPIC_API_KEY is not set. Set it in backend/.env or as an "
                "environment variable to enable chat."
            )
        self._model = model or settings.anthropic_model
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=30.0)

    def generate(self, system: str, history: list[dict], tools: list[ToolSpec]) -> LLMTurn:
        try:
            response = self._client.post(
                self._base_url,
                headers={
                    "x-api-key": self._api_key,
                    "anthropic-version": ANTHROPIC_VERSION,
                    "content-type": "application/json",
                },
                json={
                    "model": self._model,
                    "max_tokens": 1024,
                    "system": system,
                    "messages": _translate_history(history),
                    "tools": _translate_tools(tools),
                },
            )
            response.raise_for_status()
            payload = response.json()

            text_parts = []
            tool_calls = []
            for block in payload.get("content", []):
                if block["type"] == "text":
                    text_parts.append(block["text"])
                elif block["type"] == "tool_use":
                    tool_calls.append(
                        ToolCall(id=block["id"], name=block["name"], input=block["input"])
                    )

            return LLMTurn(
                text="".join(text_parts) or None,
                tool_calls=tool_calls,
                stop_reason=payload.get("stop_reason", "end_turn"),
            )
        finally:
            if self._owns_client:
                self._client.close()
```

Note: `json` is imported but unused directly in this file (translation builds dicts, and `httpx`'s `json=` param serializes them) — remove the `import json` line if your editor/linter flags it; it is not required by the code above.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `.venv/Scripts/python.exe -m pytest tests/test_anthropic_llm_provider.py -v` (from `backend/`)
Expected: PASS, all 7 tests.

- [ ] **Step 8: Commit**

```bash
git add backend/app/config.py backend/app/providers/llm.py backend/app/providers/anthropic.py backend/.env.example backend/tests/test_anthropic_llm_provider.py
git commit -m "feat: add LLMProvider abstraction and AnthropicLLMProvider adapter"
```

---

### Task 2: Extract alert/marine query services + build the chat tool registry

**Files:**
- Create: `backend/app/warning/service.py`
- Create: `backend/app/marine/service.py`
- Modify: `backend/app/main.py`
- Create: `backend/app/chat/__init__.py` (empty)
- Create: `backend/app/chat/tools.py`
- Test: `backend/tests/test_warning_service.py`
- Test: `backend/tests/test_marine_service.py`
- Test: `backend/tests/test_chat_tools.py`

**Interfaces:**
- Consumes: `get_weather` (`app/weather/service.py`), `geocode_place` (`app/geocoding/service.py`), `get_metar` (`app/aviation/service.py`) — all already exist with signatures shown in Task 1's context above.
- Produces: `list_alerts() -> list[dict]` in `app/warning/service.py`; `list_pfz_zones() -> list[dict]` in `app/marine/service.py`; `TOOL_SPECS: list[ToolSpec]` and `execute_tool(name: str, tool_input: dict) -> str` in `app/chat/tools.py`, consumed by Task 3's orchestration loop.

`main.py` currently has this (read it to confirm before editing — it should match):

```python
@app.get("/alerts")
def list_alerts() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    return [
        {k: v for k, v in row.items() if k != "raw_payload"}
        for row in rows
    ]
```

and

```python
@app.get("/marine/pfz-zones")
def list_pfz_zones() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    return [
        {k: v for k, v in row.items() if k != "raw_payload"}
        for row in rows
    ]
```

This task moves the query logic (not the route) into service modules, so both the HTTP routes and the new chat tools call one shared implementation — this is a plain extraction, the query logic itself does not change.

- [ ] **Step 1: Write the failing test for `app/warning/service.py`**

Create `backend/tests/test_warning_service.py`:

```python
from datetime import datetime, timezone

from app.ingestion.alerts import ingest_alerts
from app.warning.service import list_alerts
from tests.conftest import FakeWarningProvider
from app.providers.warning import AlertData


def test_list_alerts_returns_ingested_rows_without_raw_payload(clean_alerts_table):
    alert = AlertData(
        external_id="service-test-1",
        source="SACHET-SDMA",
        severity="Moderate",
        event_type="Flood",
        area_description="Test Area",
        effective_start_time=None,
        effective_end_time=None,
        warning_message="Test warning",
        severity_color=None,
        latitude=19.08,
        longitude=72.88,
        raw_payload={"secret": "should not leak"},
    )
    ingest_alerts(FakeWarningProvider([alert]))

    rows = list_alerts()

    matching = [r for r in rows if r["external_id"] == "service-test-1"]
    assert len(matching) == 1
    assert matching[0]["severity"] == "Moderate"
    assert "raw_payload" not in matching[0]
```

- [ ] **Step 2: Run it, verify it fails**

Run: `.venv/Scripts/python.exe -m pytest tests/test_warning_service.py -v` (from `backend/`)
Expected: FAIL — `app.warning.service` does not exist.

- [ ] **Step 3: Create `app/warning/service.py`**

```python
"""Query-path read of ingested alert rows — see app/ingestion/alerts.py for
how this table is populated (scheduled-ingestion pattern)."""

from sqlalchemy import select

from app.db import get_engine
from app.models import Alert


def list_alerts() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(Alert)).mappings().all()
    return [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]
```

- [ ] **Step 4: Run it, verify it passes**

Run: `.venv/Scripts/python.exe -m pytest tests/test_warning_service.py -v` (from `backend/`)
Expected: PASS.

- [ ] **Step 5: Write the failing test for `app/marine/service.py`**

Create `backend/tests/test_marine_service.py`:

```python
from app.ingestion.marine import ingest_pfz_zones
from app.marine.service import list_pfz_zones
from app.providers.marine import PfzZoneData
from tests.conftest import _FakeMarineProvider


def test_list_pfz_zones_returns_ingested_rows_without_raw_payload(clean_pfz_zones):
    zone = PfzZoneData(
        external_id="service-test-1",
        category="ghrsst",
        sector_boundary=2,
        sector_name="Test Sector",
        julian_day="248",
        serial_number="099",
        year=2021,
        uid=2021248099,
        length_km=12.5,
        geometry={"type": "MultiLineString", "coordinates": [[[10.0, 10.0], [11.0, 11.0]]]},
        raw_payload={"secret": "should not leak"},
    )
    ingest_pfz_zones(_FakeMarineProvider([zone]))

    rows = list_pfz_zones()

    matching = [r for r in rows if r["external_id"] == "service-test-1"]
    assert len(matching) == 1
    assert matching[0]["sector_name"] == "Test Sector"
    assert matching[0]["geometry"] == zone.geometry
    assert "raw_payload" not in matching[0]
```

- [ ] **Step 6: Run it, verify it fails**

Run: `.venv/Scripts/python.exe -m pytest tests/test_marine_service.py -v` (from `backend/`)
Expected: FAIL — `app.marine.service` does not exist.

- [ ] **Step 7: Create `app/marine/service.py`**

```python
"""Query-path read of ingested PFZ zone rows — see app/ingestion/marine.py
for how this table is populated (scheduled-ingestion pattern)."""

from sqlalchemy import select

from app.db import get_engine
from app.models import PfzZone


def list_pfz_zones() -> list[dict]:
    with get_engine().connect() as conn:
        rows = conn.execute(select(PfzZone)).mappings().all()
    return [{k: v for k, v in row.items() if k != "raw_payload"} for row in rows]
```

- [ ] **Step 8: Run it, verify it passes**

Run: `.venv/Scripts/python.exe -m pytest tests/test_marine_service.py -v` (from `backend/`)
Expected: PASS.

- [ ] **Step 9: Update `app/main.py` to use the extracted services**

Replace the `list_alerts` route body:

```python
@app.get("/alerts")
def list_alerts() -> list[dict]:
    return warning_service.list_alerts()
```

Replace the `list_pfz_zones` route body (keep the existing comment about `geometry` being deliberately included, from the marine sprint's fix wave — do not delete it):

```python
@app.get("/marine/pfz-zones")
def list_pfz_zones() -> list[dict]:
    return marine_service.list_pfz_zones()
```

Add imports near the top of `main.py`, alongside the existing `from app.ingestion...` / `from app.providers...` imports:

```python
from app.marine import service as marine_service
from app.warning import service as warning_service
```

Remove the now-unused `from sqlalchemy import select` import and the `Alert`/`PfzZone` names from `from app.models import Alert, PfzZone` in `main.py` **only if** nothing else in the file still uses them — check with `grep -n "select(\|Alert\|PfzZone" app/main.py` before removing; leave any import that's still referenced (e.g. by another route) in place.

- [ ] **Step 10: Run the full suite to confirm nothing broke**

Run: `.venv/Scripts/python.exe -m pytest tests/ -v` (from `backend/`)
Expected: all existing tests (including `test_alerts_endpoint.py` and `test_marine_endpoint.py`) still PASS — this was a behavior-preserving extraction.

- [ ] **Step 11: Commit**

```bash
git add backend/app/warning/service.py backend/app/marine/service.py backend/app/main.py backend/tests/test_warning_service.py backend/tests/test_marine_service.py
git commit -m "refactor: extract list_alerts/list_pfz_zones into service modules"
```

- [ ] **Step 12: Write the failing tests for the chat tool registry**

Create `backend/tests/test_chat_tools.py`:

```python
import json
from datetime import datetime, timezone

from sqlalchemy import insert

from app.chat.tools import TOOL_SPECS, execute_tool
from app.db import get_engine
from app.models import WeatherReading


def test_tool_specs_cover_all_five_data_sources():
    names = {spec.name for spec in TOOL_SPECS}
    assert names == {"get_weather", "geocode", "get_metar", "list_alerts", "list_pfz_zones"}


def test_execute_get_weather_returns_seeded_cache_as_json(clean_weather_readings):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=28.0,
                humidity_pct=70,
                weather_code=1,
                wind_speed_kmh=10.0,
                wind_direction_deg=180,
                observed_at="2026-09-06T12:00",
                timezone="Asia/Kolkata",
                raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    result_json = execute_tool("get_weather", {"latitude": 19.08, "longitude": 72.88})
    result = json.loads(result_json)

    assert result["temperature_c"] == 28.0
    assert "raw_payload" not in result
    assert "error" not in result


def test_execute_geocode_reports_not_found_as_in_band_error(monkeypatch):
    # geocode_place would otherwise hit the real network on a cache miss
    # with no injected provider seam (unlike get_weather/get_metar, this
    # test can't seed a Postgres cache row to avoid it — geocoding's
    # cache key is a normalized query string, not a coordinate, and
    # there is no "not found" row to seed by design, see
    # app/geocoding/service.py's docstring). Patch the name app/chat/tools.py
    # imported instead.
    import app.chat.tools as tools_module

    monkeypatch.setattr(tools_module, "geocode_place", lambda query: None)

    result_json = execute_tool("geocode", {"query": "nonexistent place"})
    result = json.loads(result_json)

    assert "error" in result


def test_execute_get_metar_missing_icao_returns_in_band_error():
    result_json = execute_tool("get_metar", {})
    result = json.loads(result_json)

    assert "error" in result


def test_execute_unknown_tool_returns_in_band_error():
    result_json = execute_tool("not_a_real_tool", {})
    result = json.loads(result_json)

    assert "error" in result
    assert "not_a_real_tool" in result["error"]


def test_execute_list_alerts_returns_json_list(clean_alerts_table):
    result_json = execute_tool("list_alerts", {})
    result = json.loads(result_json)

    assert isinstance(result, list)


def test_execute_list_pfz_zones_returns_json_list(clean_pfz_zones):
    result_json = execute_tool("list_pfz_zones", {})
    result = json.loads(result_json)

    assert isinstance(result, list)
```

Note: `app/chat/tools.py` (Step 13) must do `from app.geocoding.service import geocode_place` (a plain module-level import used as `geocode_place(...)` inside the handler) rather than importing and calling through a namespace — this is what lets the test above monkeypatch `tools_module.geocode_place` directly.

- [ ] **Step 13: Run the tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v` (from `backend/`)
Expected: FAIL — `app.chat.tools` does not exist.

- [ ] **Step 14: Create `backend/app/chat/__init__.py`** (empty file)

- [ ] **Step 15: Create `app/chat/tools.py`**

```python
"""Tool registry for the chat orchestration loop (app/chat/service.py).

Every handler here calls an existing query-path service function — never a
raw provider and never a table directly — so every tool call inherits that
service's caching behavior and its raw_payload exclusion for free. This is
the mechanical enforcement of the spec's grounding principle (section 1):
the LLM can only ever learn a fact through one of these, never invent one.
"""

import json

from app.aviation.service import get_metar
from app.geocoding.service import geocode_place
from app.marine.service import list_pfz_zones
from app.providers.llm import ToolSpec
from app.warning.service import list_alerts
from app.weather.service import get_weather

TOOL_SPECS: list[ToolSpec] = [
    ToolSpec(
        name="get_weather",
        description="Get current weather (temperature, humidity, wind) for a specific latitude/longitude coordinate.",
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
            "required": ["latitude", "longitude"],
        },
    ),
    ToolSpec(
        name="geocode",
        description="Look up the coordinates and display name for a place name (city, district, landmark).",
        input_schema={
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "A place name, e.g. 'Mumbai, India'"},
            },
            "required": ["query"],
        },
    ),
    ToolSpec(
        name="get_metar",
        description="Get the current aviation weather observation (METAR) for an airport by its 4-letter ICAO code.",
        input_schema={
            "type": "object",
            "properties": {
                "icao": {"type": "string", "description": "4-letter ICAO airport code, e.g. VABB"},
            },
            "required": ["icao"],
        },
    ),
    ToolSpec(
        name="list_alerts",
        description="List all currently active disaster/weather alerts and warnings across India.",
        input_schema={"type": "object", "properties": {}},
    ),
    ToolSpec(
        name="list_pfz_zones",
        description="List all currently advised marine Potential Fishing Zones (PFZ).",
        input_schema={"type": "object", "properties": {}},
    ),
]


def _handle_get_weather(tool_input: dict) -> dict:
    return get_weather(latitude=tool_input["latitude"], longitude=tool_input["longitude"])


def _handle_geocode(tool_input: dict) -> dict:
    result = geocode_place(tool_input["query"])
    if result is None:
        return {"error": f"No location found for '{tool_input['query']}'"}
    return result


def _handle_get_metar(tool_input: dict) -> dict:
    result = get_metar(tool_input["icao"])
    if result is None:
        return {"error": f"No current METAR observation for '{tool_input['icao']}'"}
    return result


def _handle_list_alerts(tool_input: dict) -> list[dict]:
    return list_alerts()


def _handle_list_pfz_zones(tool_input: dict) -> list[dict]:
    return list_pfz_zones()


_HANDLERS = {
    "get_weather": _handle_get_weather,
    "geocode": _handle_geocode,
    "get_metar": _handle_get_metar,
    "list_alerts": _handle_list_alerts,
    "list_pfz_zones": _handle_list_pfz_zones,
}


def execute_tool(name: str, tool_input: dict) -> str:
    handler = _HANDLERS.get(name)
    if handler is None:
        return json.dumps({"error": f"Unknown tool '{name}'"})
    try:
        result = handler(tool_input)
    except (KeyError, TypeError, ValueError) as exc:
        return json.dumps({"error": f"Invalid input for tool '{name}': {exc}"})
    return json.dumps(result, default=str)
```

Note the `default=str` on the final `json.dumps` — service functions return raw `datetime` objects (e.g. `fetched_at`) straight from a Postgres row mapping, which the stdlib `json` module cannot serialize without a fallback; `default=str` converts them to ISO-ish strings instead of raising.

- [ ] **Step 16: Run the tests to verify they pass**

Run: `.venv/Scripts/python.exe -m pytest tests/test_chat_tools.py -v` (from `backend/`)
Expected: PASS, all 7 tests.

- [ ] **Step 17: Run the full suite**

Run: `.venv/Scripts/python.exe -m pytest tests/ -v` (from `backend/`)
Expected: all tests PASS.

- [ ] **Step 18: Commit**

```bash
git add backend/app/chat/__init__.py backend/app/chat/tools.py backend/tests/test_chat_tools.py
git commit -m "feat: add chat tool registry wrapping existing query-path services"
```

---

### Task 3: Chat orchestration loop and `POST /chat` endpoint

**Files:**
- Create: `backend/app/chat/service.py`
- Modify: `backend/app/main.py`
- Modify: `backend/tests/conftest.py`
- Test: `backend/tests/test_chat_service.py`
- Test: `backend/tests/test_chat_endpoint.py`

**Interfaces:**
- Consumes: `TOOL_SPECS`, `execute_tool` (`app/chat/tools.py`, Task 2); `LLMProvider`, `LLMTurn`, `ToolCall` (`app/providers/llm.py`, Task 1); `AnthropicLLMProvider` (`app/providers/anthropic.py`, Task 1).
- Produces: `chat_turn(message: str, history: list[dict] | None = None, provider: LLMProvider | None = None) -> dict` returning `{"reply": str, "history": list[dict]}`; FastAPI dependency `get_llm_provider() -> LLMProvider` and route `POST /chat`.

- [ ] **Step 1: Add `FakeLLMProvider` to `tests/conftest.py`**

Add this import and class to `backend/tests/conftest.py`, alongside the existing `FakeWarningProvider`/`_FakeMarineProvider` fakes (same file, same convention — do not create a second copy elsewhere):

```python
from app.providers.llm import LLMTurn


class FakeLLMProvider:
    def __init__(self, turns: list[LLMTurn]):
        self._turns = list(turns)
        self.calls: list[dict] = []

    def generate(self, system, history, tools):
        self.calls.append({"system": system, "history": [dict(h) for h in history], "tools": tools})
        return self._turns.pop(0)
```

- [ ] **Step 2: Write the failing tests for the orchestration loop**

Create `backend/tests/test_chat_service.py`:

```python
from datetime import datetime, timezone

from sqlalchemy import insert

from app.chat.service import chat_turn
from app.db import get_engine
from app.models import WeatherReading
from app.providers.llm import LLMTurn, ToolCall
from tests.conftest import FakeLLMProvider


def _seed_weather():
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=28.0,
                humidity_pct=70,
                weather_code=1,
                wind_speed_kmh=10.0,
                wind_direction_deg=180,
                observed_at="2026-09-06T12:00",
                timezone="Asia/Kolkata",
                raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )


def test_chat_turn_executes_tool_call_then_returns_final_answer(clean_weather_readings):
    _seed_weather()
    provider = FakeLLMProvider(
        [
            LLMTurn(
                text=None,
                tool_calls=[
                    ToolCall(id="toolu_1", name="get_weather", input={"latitude": 19.08, "longitude": 72.88})
                ],
                stop_reason="tool_use",
            ),
            LLMTurn(text="It's 28.0C in Mumbai.", tool_calls=[], stop_reason="end_turn"),
        ]
    )

    result = chat_turn("What's the weather in Mumbai?", provider=provider)

    assert result["reply"] == "It's 28.0C in Mumbai."
    assert len(provider.calls) == 2
    # Second call's history must contain the tool result the loop executed.
    second_call_history = provider.calls[1]["history"]
    tool_messages = [m for m in second_call_history if m["role"] == "tool"]
    assert len(tool_messages) == 1
    assert "28.0" in tool_messages[0]["content"]


def test_chat_turn_returns_direct_answer_without_tool_calls():
    provider = FakeLLMProvider([LLMTurn(text="Hello!", tool_calls=[], stop_reason="end_turn")])

    result = chat_turn("Hi", provider=provider)

    assert result["reply"] == "Hello!"
    assert len(provider.calls) == 1


def test_chat_turn_stops_after_max_iterations_without_crashing():
    looping_turn = LLMTurn(
        text=None,
        tool_calls=[ToolCall(id="toolu_x", name="list_alerts", input={})],
        stop_reason="tool_use",
    )
    provider = FakeLLMProvider([looping_turn] * 5)

    result = chat_turn("loop forever", provider=provider)

    assert len(provider.calls) == 5
    assert "reply" in result
    assert result["reply"]
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest tests/test_chat_service.py -v` (from `backend/`)
Expected: FAIL — `app.chat.service` does not exist.

- [ ] **Step 4: Create `app/chat/service.py`**

```python
"""Agentic tool-calling loop for the conversational chat endpoint.

This is a fourth query-path pattern, distinct from the three caching
patterns elsewhere in this codebase (scheduled-ingestion — see
app/ingestion/alerts.py; cache-with-TTL — see app/weather/service.py;
permanent-cache — see app/geocoding/service.py): a chat reply is never
cached. Each turn is a fresh generation, since a conversational response
is inherently non-idempotent — the same question asked twice can get a
differently-phrased (and, if history differs, differently-grounded)
answer. Caching would risk serving a stale or context-mismatched reply.

The LLM only ever learns facts through app/chat/tools.py's registry,
which reads exclusively from the existing query-path services — never
directly from a provider or a raw table — per the spec's grounding
principle (WeatherGPT V1 design doc, section 1).
"""

import logging

from app.chat.tools import TOOL_SPECS, execute_tool
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.llm import LLMProvider

logger = logging.getLogger(__name__)

_MAX_TOOL_ITERATIONS = 5

_SYSTEM_PROMPT = (
    "You are WeatherGPT, a conversational assistant for weather, marine, "
    "aviation, and disaster-alert information in India. Always use the "
    "provided tools to look up current facts — never state a specific "
    "weather value, alert, or observation from memory. If a tool reports "
    "an error or no data, say so plainly rather than guessing."
)


def chat_turn(
    message: str,
    history: list[dict] | None = None,
    provider: LLMProvider | None = None,
) -> dict:
    llm = provider or AnthropicLLMProvider()
    conversation = list(history or [])
    conversation.append({"role": "user", "content": message})

    for _ in range(_MAX_TOOL_ITERATIONS):
        turn = llm.generate(system=_SYSTEM_PROMPT, history=conversation, tools=TOOL_SPECS)

        if turn.tool_calls:
            conversation.append(
                {
                    "role": "assistant",
                    "content": turn.text or "",
                    "tool_calls": [
                        {"id": call.id, "name": call.name, "input": call.input}
                        for call in turn.tool_calls
                    ],
                }
            )
            for call in turn.tool_calls:
                result = execute_tool(call.name, call.input)
                conversation.append(
                    {"role": "tool", "tool_call_id": call.id, "content": result}
                )
            continue

        conversation.append({"role": "assistant", "content": turn.text or ""})
        return {"reply": turn.text or "", "history": conversation}

    logger.warning(
        "Chat turn hit max tool-call iterations (%d) without a final answer",
        _MAX_TOOL_ITERATIONS,
    )
    return {
        "reply": "I wasn't able to finish looking that up — please try rephrasing your question.",
        "history": conversation,
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `.venv/Scripts/python.exe -m pytest tests/test_chat_service.py -v` (from `backend/`)
Expected: PASS, all 3 tests.

- [ ] **Step 6: Commit**

```bash
git add backend/tests/conftest.py backend/app/chat/service.py backend/tests/test_chat_service.py
git commit -m "feat: add chat orchestration loop with tool-call iteration cap"
```

- [ ] **Step 7: Write the failing test for `POST /chat`**

Create `backend/tests/test_chat_endpoint.py`:

```python
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
```

- [ ] **Step 8: Run the tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest tests/test_chat_endpoint.py -v` (from `backend/`)
Expected: FAIL — no `/chat` route, `get_llm_provider` does not exist.

- [ ] **Step 9: Add the `/chat` route to `app/main.py`**

Add these imports near the top of `main.py`:

```python
from fastapi import Depends
from pydantic import BaseModel

from app.chat.service import chat_turn
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.llm import LLMProvider
```

Add this dependency function and route at the end of `main.py`:

```python
class ChatRequest(BaseModel):
    message: str
    history: list[dict] | None = None


def get_llm_provider() -> LLMProvider:
    return AnthropicLLMProvider()


@app.post("/chat")
def chat_endpoint(
    request: ChatRequest, llm: LLMProvider = Depends(get_llm_provider)
) -> dict:
    return chat_turn(request.message, request.history, provider=llm)
```

`get_llm_provider` is a real FastAPI `Depends` seam (not the plain-DI-parameter pattern every other route in this file uses) precisely because this is the one route where the "obvious" call — `chat_turn(request.message, request.history)` with no provider — would reach a live, uncachable, per-call external API on every single test run. Every other route's underlying service function only reaches its provider on a cache miss, so seeding Postgres directly is enough to keep tests offline; chat has no cache to seed. Document this one-line rationale as a comment directly above `get_llm_provider` in `main.py`.

- [ ] **Step 10: Run the tests to verify they pass**

Run: `.venv/Scripts/python.exe -m pytest tests/test_chat_endpoint.py -v` (from `backend/`)
Expected: PASS, both tests.

- [ ] **Step 11: Run the full suite**

Run: `.venv/Scripts/python.exe -m pytest tests/ -v` (from `backend/`)
Expected: all tests PASS (baseline 54 + this plan's new tests).

- [ ] **Step 12: Manual live verification (non-blocking, requires a real API key)**

This step cannot run in the automated suite or without a real `ANTHROPIC_API_KEY`, and is not required for the task to be marked complete — it is the same "one manual live-verification step" every prior sprint has included for its real external call. Skip it if no key is available yet; note in the task report that it was skipped and why.

If a key is available, from `backend/` with `ANTHROPIC_API_KEY` set in `.env` or the shell environment:

```bash
.venv/Scripts/python.exe -c "
from app.chat.service import chat_turn
result = chat_turn('What tools do you have access to? List their names only.')
print(result['reply'])
"
```

Expected: a real response naming the five tools (or a natural-language description of their purposes) — confirms the live request/response translation round-trip actually works end to end against the real API, not just against `httpx.MockTransport`.

- [ ] **Step 13: Commit**

```bash
git add backend/app/main.py backend/tests/test_chat_endpoint.py
git commit -m "feat: add POST /chat endpoint with Depends-based LLM provider override"
```
